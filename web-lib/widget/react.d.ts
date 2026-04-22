// Minimal declarations for the subset of the `react` module that this widget
// uses. The full React API is provided at runtime by the Lean InfoView
// environment that loads the widget; we only need enough types for the bits
// referenced here to type-check.

declare module "react" {
    type ReactNode = unknown;
    interface CSSProperties {
        [key: string]: string | number | undefined;
    }
    export function createElement(
        type: string,
        props?: Record<string, unknown> | null,
        ...children: ReactNode[]
    ): ReactNode;
}
