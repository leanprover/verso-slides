"""Tests that #eval, #check, #print, and #reduce output appears
after the command, not at the end of the code block."""

from bs4 import BeautifulSoup


def _get_slide_code_children(doc, slide_title):
    """Find the code block in a slide and return (ordered) list of
    ('code', text) for code tokens or ('output', text) for command output divs."""
    sections = doc.select("section")
    for s in sections:
        h = s.find(["h1", "h2", "h3"])
        if h and slide_title in h.get_text():
            code = s.select_one("code.hl.lean.block")
            assert code, f"No code block found in slide '{slide_title}'"
            items = []
            for child in code.children:
                if (
                    hasattr(child, "name")
                    and child.name == "div"
                    and "command-output" in (child.get("class") or [])
                ):
                    items.append(("output", child.get_text().strip()))
                elif hasattr(child, "name"):
                    text = child.get_text().strip()
                    if text:
                        items.append(("code", text))
            return items
    raise AssertionError(f"Slide '{slide_title}' not found")


class TestEvalMultiline:
    def test_eval_multiline_output_after_expression(self, code_doc: BeautifulSoup):
        """#eval output should appear after the full expression, even when it spans multiple lines."""
        items = _get_slide_code_children(code_doc, "Eval Multiline")
        outputs = [(i, kind, text) for i, (kind, text) in enumerate(items) if kind == "output"]
        assert len(outputs) == 1, f"Expected 1 output, got {len(outputs)}"

        output_idx, _, output_text = outputs[0]
        assert "6" in output_text

        # The expression tokens (1, +, 2, 3) should all come before the output
        expr_indices = [
            i for i, (k, t) in enumerate(items)
            if k == "code" and t in ("1", "2", "3", "+")
        ]
        assert all(i < output_idx for i in expr_indices), \
            "Expression tokens should appear before the output"


class TestEvalOrdering:
    def test_eval_outputs_interleaved(self, code_doc: BeautifulSoup):
        """#eval outputs should appear after each command, not at the end."""
        items = _get_slide_code_children(code_doc, "Eval Ordering")
        outputs = [(kind, text) for kind, text in items if kind == "output"]
        assert len(outputs) == 3

        output_first_idx = next(
            i for i, (k, t) in enumerate(items) if k == "output" and "first" in t
        )
        def_idx = next(
            i for i, (k, t) in enumerate(items) if k == "code" and t == "evalMiddle"
        )
        output_second_idx = next(
            i for i, (k, t) in enumerate(items) if k == "output" and "4" in t and "first" not in t
        )
        output_third_idx = next(
            i for i, (k, t) in enumerate(items) if k == "output" and "8" in t
        )

        # First output before the def, second and third after it
        assert output_first_idx < def_idx, \
            "First #eval output should appear before 'def evalMiddle'"
        assert output_second_idx > def_idx, \
            "Second #eval output should appear after 'def evalMiddle'"
        # Each output appears exactly once, in order
        assert output_first_idx < output_second_idx < output_third_idx, \
            "Outputs should appear in command order"

    def test_check_outputs_interleaved(self, code_doc: BeautifulSoup):
        """#check outputs should appear after each command, not at the end."""
        items = _get_slide_code_children(code_doc, "Check Ordering")
        outputs = [(kind, text) for kind, text in items if kind == "output"]
        assert len(outputs) == 2

        output1_idx = next(
            i for i, (k, t) in enumerate(items) if k == "output" and "Nat" in t
        )
        def_middle_idx = next(
            i for i, (k, t) in enumerate(items) if k == "code" and t == "checkMiddle" and i > output1_idx
        )
        output2_idx = next(
            i for i, (k, t) in enumerate(items) if k == "output" and "String" in t
        )

        assert output1_idx < def_middle_idx, \
            "First #check output should appear before 'def checkMiddle'"
        assert output2_idx > def_middle_idx, \
            "Second #check output should appear after 'def checkMiddle'"

    def test_print_outputs_interleaved(self, code_doc: BeautifulSoup):
        """#print outputs should appear after each command, not at the end."""
        items = _get_slide_code_children(code_doc, "Print Ordering")
        outputs = [(kind, text) for kind, text in items if kind == "output"]
        assert len(outputs) == 2

        output1_idx = next(
            i for i, (k, t) in enumerate(items) if k == "output" and "100" in t
        )
        def_middle_idx = next(
            i for i, (k, t) in enumerate(items) if k == "code" and t == "printMiddle" and i > output1_idx
        )
        output2_idx = next(
            i for i, (k, t) in enumerate(items) if k == "output" and "true" in t
        )

        assert output1_idx < def_middle_idx, \
            "First #print output should appear before 'def printMiddle'"
        assert output2_idx > def_middle_idx, \
            "Second #print output should appear after 'def printMiddle'"

    def test_reduce_outputs_interleaved(self, code_doc: BeautifulSoup):
        """#reduce outputs should appear after each command, not at the end."""
        items = _get_slide_code_children(code_doc, "Reduce Ordering")
        outputs = [(kind, text) for kind, text in items if kind == "output"]
        assert len(outputs) == 2

        output1_idx = next(
            i for i, (k, t) in enumerate(items) if k == "output" and t == "5"
        )
        def_middle_idx = next(
            i for i, (k, t) in enumerate(items) if k == "code" and t == "reduceMiddle"
        )
        output2_idx = next(
            i for i, (k, t) in enumerate(items) if k == "output" and t == "20"
        )

        assert output1_idx < def_middle_idx, \
            "First #reduce output should appear before 'def reduceMiddle'"
        assert output2_idx > def_middle_idx, \
            "Second #reduce output should appear after 'def reduceMiddle'"
