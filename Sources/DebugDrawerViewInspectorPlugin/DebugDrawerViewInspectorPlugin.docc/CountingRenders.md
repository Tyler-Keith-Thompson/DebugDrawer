# Counting Renders

Find the views that keep re-rendering.

## Overview

The View Inspector plugin counts how many times a view's body is evaluated, for the views the app
names with `.trackRenders(_:)`. The modifier counts each time the body that applies it runs, so
apply it to the outermost view of the body to count:

```swift
import DebugDrawerViewInspectorPlugin

struct OrderRow: View {
    let title: String
    let total: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(total)
        }
        .trackRenders("OrderRow")
    }
}
```

The plugin's SwiftUI Renders section lists each name with its count, busiest first, and Reset
starts the counts over. A row that renders again when nothing it shows has changed is reading state
it doesn't need. Flash Renders outlines a tracked view each time its body runs, unless Reduce
Motion is on. The drawer tracks none of its own views, so only the app's appear. In release builds
`.trackRenders(_:)` returns the view unchanged.
