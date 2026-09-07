# Lucide icons — MyCoffee redesign

Twelve files, one per icon in §11 of `UPDATE_BRIEF.md`. Source: [lucide.dev](https://lucide.dev), ISC licence. Open `index.html` to see the set.

All files: `24×24` viewBox, `fill="none"`, `stroke="currentColor"`, `stroke-width="1.7"`, round caps and joins. `heart-fill.svg` is the only filled asset — used solely for an active favourite.

| File | Used for |
| --- | --- |
| `sliders-horizontal.svg` | Nav bar — sort |
| `settings.svg` | Nav bar — settings |
| `coffee.svg` | Tab — Coffees |
| `circle-plus.svg` | Tab — Add |
| `bar-chart-3.svg` | Tab — Insights |
| `heart.svg` / `heart-fill.svg` | Favourite, off / on |
| `search.svg` | Search field |
| `chevron-left.svg` | Detail hero — back |
| `share.svg` | Detail hero — share |
| `pencil.svg` | Detail hero — edit |
| `chevron-right.svg` | Disclosure, review nudge |

## Vendoring into Xcode

1. Drag all twelve SVGs into `Assets.xcassets`. For each: Attributes inspector → **Render As: Template Image**, **Scales: Single Scale**, **Preserve Vector Data: on**.
2. Name the image sets exactly as the files (`sliders-horizontal`, `heart-fill`, …).
3. Use them through one wrapper so sizing and stroke stay uniform:

```swift
struct Icon: View {
    let name: String
    var size: CGFloat = 22

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
```

Sizes per the brief: **22** in the nav bar, **25** in the tab bar, **14–19** inline. Tint with `.foregroundStyle(...)` at the call site; never bake a colour into the asset.

```swift
// nav bar
ToolbarItem(placement: .topBarTrailing) {
    Button { showSort = true } label: { Icon(name: "sliders-horizontal") }
}

// tab bar — label the Image directly, SwiftUI applies tab-bar sizing
Tab("Coffees", image: "coffee") { CoffeesView() }

// favourite
Icon(name: isFavourite ? "heart-fill" : "heart", size: 19)
    .foregroundStyle(isFavourite ? .red : .secondary)
```

The stroke width is baked into the vector at 1.7, so do **not** apply `.fontWeight` or `.symbolRenderingMode` — those only affect SF Symbols and will silently do nothing here.
