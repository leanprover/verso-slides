import { createElement as h } from "react";
/**
 * @param {{ src: string; alt?: string }} props
 */
export default function (props) {
    return h("img", { src: props.src, alt: props.alt || "", style: { maxWidth: "100%" } });
}
