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

    func existingInstance() -> S? {
        return registration.instance
    }
}

public extension WorkflowNode {
    public func on<New>(_ transition: S.Out, connect node: WorkflowNode<New>, connector: @escaping (S,New) -> Void) {
        on(transition, bridge: node, with: New.In.self, bridge: { $0 }, connector: connector)
    }

    public func on<New>(_ transition: S.Out, connect node: WorkflowNode<New>, passing value: @autoclosure @escaping () -> New.In, connector: @escaping (S,New) -> Void) {
        on(transition, bridge: node, with: New.In.self, bridge: { _ in value() }, connector: connector)
    }

    public func on<New>(_ transition: S.Out, push node: WorkflowNode<New>, animated: Bool) {
        on(transition, bridge: node, with: New.In.self, bridge: { $0 }) { source, destination in
            source.view.push(destination.view, animated: animated)
        }
    }

    public func on<New>(_ transition: S.Out, present node: WorkflowNode<New>, animated: Bool) {
        on(transition, bridge: node, with: New.In.self, bridge: { $0 }) { source, destination in
            source.view.present(destination.view, animated: animated)
        }
    }

    public func on<New, Arg>(_ transition: S.Out, bridge node: WorkflowNode<New>, with arg: Arg.Type, bridge: @escaping (Arg) -> New.In, connector: @escaping (S,New) -> Void) {
        print("\(Arg.self) vs \(transition.name)")
        guard let transition: Transition<Arg> = transition.asTransition() else {
            debugPrint("[N] Wrong transition type set")
            assertionFailure("[N]  Wrong transition type set")
            return
        }
        debugPrint("[N] [\(name)] adding \(transition.name) to \(node.name)")
        let connect: (Arg,S) -> Void = { output, source in
            let input = bridge(output)
            let destination = node.resolve(with: input) // keep destination node alive
            connector(source, destination)
        }
        connectors[transition.id] = connect
    }

    public func on<New>(_ transition: S.Out..., unwind node: WorkflowNode<New>, connector: @escaping (S,New?) -> Void) {
        transition.forEach { transition in
            guard let transition: Transition<Void> = transition.asTransition() else {
                debugPrint("[N] Wrong transition type set")
                assertionFailure("[N]  Wrong transition type set")
                return
            }
            debugPrint("[N] [\(name)] adding \(transition.name) to \(node.name)")
            let connect: (Void,S) -> Void = { output, source in
                let destination = node.existingInstance()
                connector(source, destination)
            }
            connectors[transition.id] = connect
        }
    }
}

public extension WorkflowNode {
    /// When no arguments to pass, end flow with Void type ending.
    ///
    /// - Parameters:
    ///   - transition: Transition of Void type
    ///   - flow: flow to finish (perform end transition on it)
    ///   - ending: flow ending to perform
    public func on<F>(_ transition: S.Out, end flow: F, with ending: F.Out) where F: WorkflowType, F: Navigatable {
        on(transition, finish: flow, with: Void.self) { flow, _ in
            flow.perform(ending)
        }
    }
    /// When ending requires argument, specify its type. Matching is not check on compile time!!!
    ///
    /// - Parameters:
    ///   - transition: Transition of arg type
    ///   - flow: Flow to finish (perform transition on it)
    ///   - ending: flow ending to perform, transition of arg type
    ///   - arg: Type of argument passed (must match both transitions!!!)
    public func on<F,Arg>(_ transition: S.Out, end flow: F, with ending: F.Out, and arg: Arg.Type) where F: WorkflowType, F: Navigatable {
        on(transition, finish: flow, with: Arg.self) { flow, _ in
            flow.perform(ending)
        }
    }

    /// Custom ending, do not trigger anything on flow, just calls outro closure with passed argument.
    ///
    /// - Parameters:
    ///   - transition: Transition of arg type
    ///   - flow: Flow to end
    ///   - arg: Argument type
    ///   - outro: Closure executed upon ending - should call manually perform on flow here
    public func on<F,Arg>(_ transition: S.Out, finish flow: F, with arg: Arg.Type, outro: @escaping (F,Arg) -> Void) where F: WorkflowType, F: Navigatable {
        guard let transition: Transition<Arg> = transition.asTransition() else {
            assertionFailure("Wrong type")
            return
        }
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
