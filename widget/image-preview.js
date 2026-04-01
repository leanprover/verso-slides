import { createElement as h } from "react";
export default function(props) {
  return h("img", { src: props.src, alt: props.alt || "", style: { maxWidth: "100%" } });
}
