#if DEBUG
    /// The class of a tracked object, by the names the drawer shows and groups it under.
    struct TrackedClass: Hashable, Sendable {
        /// The name as code writes it: `ProfileViewController`.
        let name: String
        /// The name with its module, which tells apart two classes of the same name:
        /// `Example.ProfileViewController`. Suspects are grouped by it.
        let qualifiedName: String
    }

    extension TrackedClass {
        /// The class of `object`.
        init(of object: AnyObject) {
            let type: AnyClass = type(of: object)
            self.init(name: String(describing: type), qualifiedName: String(reflecting: type))
        }
    }
#endif
