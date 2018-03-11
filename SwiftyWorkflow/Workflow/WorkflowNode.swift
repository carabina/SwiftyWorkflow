import Foundation

public class WorkflowNode<S: Navigatable> {
    let id: ID = UUID().uuidString
    var name: String { return "<\(String(describing: S.self)) : \(id)>" }
    fileprivate let registration: Workflow.Registration<S>
    fileprivate var connectors: [String: Any] = [:]

    init(_ registration: Workflow.Registration<S>) {
        self.registration = registration
    }

    deinit {
        debugPrint("[N] Released \(name)")
    }

    func resolve(with input: S.In) -> S {
        debugPrint("[N] Resolving \(name)")
        let controller = registration.build(with: input)
        controller.flowNavigation = self
        return controller
    }
}

public extension WorkflowNode {
    public func connect<New, Arg>(to node: WorkflowNode<New>, for transition: Transition<Arg>, connector: @escaping (S,New) -> Void) where New.In == Arg {
        bridge(to: node, for: transition, bridge: { $0 }, connector: connector)
    }

    public func bridge<New, Arg>(to node: WorkflowNode<New>, for transition: Transition<Arg>, bridge: @escaping (Arg) -> New.In, connector: @escaping (S,New) -> Void) {
        debugPrint("[N] [\(name)] adding \(transition.name) to \(node.name)")
        let connect: (Arg,S) -> Void = { output, source in
            let input = bridge(output)
            let destination = node.resolve(with: input) // keep destination node alive
            connector(source, destination)
        }
        connectors[transition.id] = connect
    }

    public func end<F>(flow: F) where F: WorkflowType, F: Navigatable {
        finish(flow: flow, with: Workflow.end, outro: { flow, _ in
            flow.perform(Workflow.end)
        })
    }

    public func end<F>(flow: F, outro: @escaping (F) -> Void) where F: WorkflowType, F: Navigatable {
        finish(flow: flow, with: Workflow.end, outro: { flow, _ in outro(flow) })
    }

    public func cancel<F>(flow: F) where F: WorkflowType, F: Navigatable {
        finish(flow: flow, with: Workflow.cancel, outro: { flow, _ in
            flow.perform(Workflow.cancel)
        })
    }

    public func cancel<F>(flow: F, outro: @escaping (F) -> Void) where F: WorkflowType, F: Navigatable {
        finish(flow: flow, with: Workflow.cancel, outro: { flow, _ in outro(flow) })
    }

    public func finish<F>(flow: F, with transition: Transition<Void>, outro: @escaping (F) -> Void) where F: WorkflowType, F: Navigatable {
        finish(flow: flow, with: transition, outro: { flow, _ in outro(flow) })
    }

    public func finish<F,Arg>(flow: F, with transition: Transition<Arg>, outro: @escaping (F,Arg) -> Void) where F: WorkflowType, F: Navigatable {
        let ending: (Arg) -> Void = { argument in
            outro(flow, argument)
        }
        connectors[transition.id] = ending
    }
}

// MARK: - NavigationProvider
extension WorkflowNode: NavigationProvider{
    public func move<S>(_ transition: Transition<Void>, from source: S) throws {
        try move(transition, with: (), from: source)
    }

    public func move<Arg,S>(_ transition: Transition<Arg>, with argument: Arg, from source: S) throws {
        guard let registered = connectors[transition.id] else {
            throw TransitionError.notSet
        }

        if let connector = registered as? (Arg,S) -> Void {
            connector(argument,source)
        } else if let outro = registered as? (Arg) -> Void {
            outro(argument)
        } else {
            throw TransitionError.wrongType
        }
    }
}