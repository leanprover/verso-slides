"""Tests for the :::table directive — DOM structure and CSS output."""

from pathlib import Path

from conftest import goto_slide_by_title


class TestTableStructure:
    def test_tables_present(self, markup_doc):
        """Five slide-table elements should be present in the markup fixture."""
        tables = markup_doc.select("table.slide-table")
        assert len(tables) == 5

    def test_col_headers_thead(self, markup_doc):
        """First table (colHeaders): should have a <thead> element."""
        table = markup_doc.select("table.slide-table")[0]
        assert table.select_one("thead") is not None

    def test_col_headers_scope(self, markup_doc):
        """First table (colHeaders): header cells should have scope='col'."""
        table = markup_doc.select("table.slide-table")[0]
        col_ths = table.select("thead th[scope='col']")
        assert len(col_ths) == 3

    def test_row_headers_scope(self, markup_doc):
        """First table (rowHeaders): first cell of each body row should have scope='row'."""
        table = markup_doc.select("table.slide-table")[0]
        row_ths = table.select("tbody th[scope='row']")
        assert len(row_ths) == 2

    def test_body_data_cells(self, markup_doc):
        """First table: non-header body cells should be <td>."""
        table = markup_doc.select("table.slide-table")[0]
        tds = table.select("tbody td")
        assert len(tds) == 4  # 2 rows × 2 data cols

    def test_first_table_classes(self, markup_doc):
        """First table: should have all expected CSS classes."""
        table = markup_doc.select("table.slide-table")[0]
        classes = table.get("class", [])
        assert "striped-rows" in classes
        assert "col-seps"     in classes
        assert "header-sep"   in classes
        assert "with-border"  in classes

    def test_second_table_classes(self, markup_doc):
        """Second table (stripedCols + rowSeps): should have correct CSS classes."""
        table = markup_doc.select("table.slide-table")[1]
        classes = table.get("class", [])
        assert "striped-cols" in classes
        assert "row-seps"     in classes
        assert "striped-rows" not in classes

    def test_second_table_no_thead(self, markup_doc):
        """Second table has no colHeaders flag: no <thead> should be present."""
        table = markup_doc.select("table.slide-table")[1]
        assert table.select_one("thead") is None

    def test_checkerboard_table_classes(self, markup_doc):
        """Third table (stripedRows + stripedCols): both classes present for checkerboard."""
        table = markup_doc.select("table.slide-table")[2]
        classes = table.get("class", [])
        assert "striped-rows" in classes
        assert "striped-cols" in classes

    def test_cell_gap_inline_style(self, markup_doc):
        """Fourth table (cellGap): should have --slide-table-cell-padding in inline style."""
        table = markup_doc.select("table.slide-table")[3]
        style = table.get("style", "")
        assert "--slide-table-cell-padding" in style
        assert "0.6em 1.2em" in style

    def test_cell_gap_table_col_headers(self, markup_doc):
        """Fourth table also has colHeaders: should have <thead>."""
        table = markup_doc.select("table.slide-table")[3]
        assert table.select_one("thead") is not None

    def test_table_css_link_in_head(self, markup_doc):
        """The page head should contain a <link> to table.css."""
        links = markup_doc.select("link[href$='table.css']")
        assert len(links) == 1

    def test_no_row_headers_on_first_col_header_row(self, markup_doc):
        """First table header row: cells should be th[scope=col], not th[scope=row]."""
        table = markup_doc.select("table.slide-table")[0]
        # Header cells should all be scope=col (rowHeaders does not apply to thead)
        header_cells = table.select("thead tr th")
        for cell in header_cells:
            assert cell.get("scope") == "col"


class TestTableCssFile:
    def test_table_css_file_exists(self, site_dir):
        """lib/table.css should be written to the built output directory."""
        css_path = site_dir / "markup" / "lib" / "table.css"
        assert css_path.exists(), f"Expected table.css at {css_path}"

    def test_table_css_has_stripe_variables(self, site_dir):
        """table.css should define both row stripe custom properties."""
        css = (site_dir / "markup" / "lib" / "table.css").read_text()
        assert "--slide-table-stripe-row-a" in css
        assert "--slide-table-stripe-row-b" in css
        assert "--slide-table-stripe-col-a" in css
        assert "--slide-table-stripe-col-b" in css

    def test_table_css_uses_theme_color(self, site_dir):
        """table.css should derive colors from currentColor via color-mix()."""
        css = (site_dir / "markup" / "lib" / "table.css").read_text()
        assert "currentColor" in css
        assert "color-mix" in css

    def test_table_css_has_checker_variables(self, site_dir):
        """table.css should define exactly two checker custom properties (-a, -b)
        for strict 2-colour alternation — no 4-value gradient."""
        css = (site_dir / "markup" / "lib" / "table.css").read_text()
        assert "--slide-table-checker-a:" in css
        assert "--slide-table-checker-b:" in css
        # Make sure the old 4-value gradient variables are gone.
        assert "--slide-table-checker-aa" not in css
        assert "--slide-table-checker-ab" not in css
        assert "--slide-table-checker-ba" not in css
        assert "--slide-table-checker-bb" not in css


def _table_style_data(page, table_index):
    """Return computed style data for every row and cell of one table, plus table border.

    Result: ``{"table_border_*": str, "rows": [{"row","bg"}, ...],
              "cells": [{"tag","row","col","bg","bt","bb","bl","br","padding"}, ...]}``

    Row backgrounds are captured separately because stripedRows applies ``background``
    to the ``<tr>`` (not the ``<td>``), and ``getComputedStyle(td).backgroundColor`` does
    not reflect the row's background.
    """
    return page.evaluate(
        """(idx) => {
            const table = document.querySelectorAll('table.slide-table')[idx];
            const tableCs = getComputedStyle(table);
            const cells = [];
            const rowBgs = [];
            const rows = table.querySelectorAll('tr');
            rows.forEach((tr, rIdx) => {
                rowBgs.push({ row: rIdx, bg: getComputedStyle(tr).backgroundColor });
                tr.querySelectorAll('th,td').forEach((cell, cIdx) => {
                    const cs = getComputedStyle(cell);
                    cells.push({
                        tag: cell.tagName.toLowerCase(),
                        row: rIdx,
                        col: cIdx,
                        bg: cs.backgroundColor,
                        bt: cs.borderTopWidth + ' ' + cs.borderTopStyle,
                        bb: cs.borderBottomWidth + ' ' + cs.borderBottomStyle,
                        bl: cs.borderLeftWidth + ' ' + cs.borderLeftStyle,
                        br: cs.borderRightWidth + ' ' + cs.borderRightStyle,
                        padding: cs.padding,
                    });
                });
            });
            return {
                table_border_top: tableCs.borderTopWidth + ' ' + tableCs.borderTopStyle,
                table_border_bottom: tableCs.borderBottomWidth + ' ' + tableCs.borderBottomStyle,
                rows: rowBgs,
                cells,
            };
        }""",
        table_index,
    )


def _is_visible_bg(bg):
    """Truthy for any background that isn't transparent/alpha-zero."""
    if not bg or bg in ("transparent", "rgba(0, 0, 0, 0)"):
        return False
    if bg.startswith("rgba(") and bg.rstrip(")").split(",")[-1].strip() == "0":
        return False
    return True


def _no_visible_border(line):
    """Truthy when border width is 0 or border-style is none (regardless of width)."""
    width, _, style = line.partition(" ")
    return width == "0px" or style == "none"


class TestTableComputedStyles:
    """Load the markup fixture in a browser and verify computed styles match flags.

    These guard against CSS regressions (selector typos, reveal.js theme
    interactions) that static DOM tests cannot catch.
    """

    def test_table1_has_row_stripes(self, page, markup_url):
        """Table 0 (+stripedRows …): body rows should alternate background colors.

        stripedRows sets the background on the ``<tr>``, so we query row bgs.
        """
        goto_slide_by_title(page, markup_url, "Tables")
        data = _table_style_data(page, 0)
        body_rows = [r for r in data["rows"] if r["row"] >= 1]
        row1_bg = next(r["bg"] for r in body_rows if r["row"] == 1)
        row2_bg = next(r["bg"] for r in body_rows if r["row"] == 2)
        assert _is_visible_bg(row1_bg), f"odd body row should be visibly striped, got {row1_bg}"
        assert row1_bg != row2_bg, f"striped rows should alternate, got {row1_bg} / {row2_bg}"

    def test_table1_has_col_seps_border(self, page, markup_url):
        """Table 0 (+colSeps): all but the first cell in each row have a left border."""
        goto_slide_by_title(page, markup_url, "Tables")
        data = _table_style_data(page, 0)
        for c in data["cells"]:
            if c["col"] == 0:
                continue
            assert not _no_visible_border(c["bl"]), \
                f"+colSeps should draw left border on col>0 cells, got {c['bl']} (row={c['row']}, col={c['col']})"

    def test_table1_has_outer_border(self, page, markup_url):
        """Table 0 (+border): the table element has a visible border."""
        goto_slide_by_title(page, markup_url, "Tables")
        data = _table_style_data(page, 0)
        assert not _no_visible_border(data["table_border_top"]), \
            f"+border should produce a visible top border, got {data['table_border_top']}"

    def test_table1_has_header_sep(self, page, markup_url):
        """Table 0 (+headerSep): data-column thead cells have 2px bottom border."""
        goto_slide_by_title(page, markup_url, "Tables")
        data = _table_style_data(page, 0)
        # Table 0 has +rowHeaders, so col=0 is a corner cell with no bottom border
        # (tested separately below). Data columns (col >= 1) must have the 2px sep.
        data_thead = [c for c in data["cells"] if c["row"] == 0 and c["col"] >= 1]
        assert data_thead, "table 0 should have data thead cells"
        for c in data_thead:
            width = c["bb"].split(" ")[0]
            assert width == "2px", f"+headerSep thead bottom should be 2px, got {c['bb']}"

    def test_table1_header_sep_corner(self, page, markup_url):
        """Table 0 (+colHeaders +rowHeaders +headerSep): the top-left corner cell must
        have NO thick border on any side — the horizontal sep only starts at the
        data-area corner (below Closes?), and the vertical sep only starts at the
        data-area corner (right of exact). Neither should protrude into/through
        the thead corner cell."""
        goto_slide_by_title(page, markup_url, "Tables")
        data = _table_style_data(page, 0)
        corner = next(c for c in data["cells"] if c["row"] == 0 and c["col"] == 0)
        assert _no_visible_border(corner["bb"]), \
            f"corner thead cell should have no bottom border, got {corner['bb']}"
        # border-right of thead[0] should not carry the thick header-sep —
        # otherwise the vertical row-header line would protrude up into thead.
        br_width = corner["br"].split(" ")[0]
        assert br_width != "2px", \
            f"corner thead cell should NOT have 2px right border (that protrudes into thead), got {corner['br']}"

    def test_table2_has_col_stripes(self, page, markup_url):
        """Table 1 (+stripedCols): adjacent columns should have different backgrounds."""
        goto_slide_by_title(page, markup_url, "Tables")
        data = _table_style_data(page, 1)
        row0 = sorted((c for c in data["cells"] if c["row"] == 0), key=lambda c: c["col"])
        assert len(row0) >= 2
        col0_bg, col1_bg = row0[0]["bg"], row0[1]["bg"]
        assert _is_visible_bg(col0_bg), f"first column of +stripedCols should have a stripe, got {col0_bg}"
        assert col0_bg != col1_bg, f"adjacent columns should differ, got {col0_bg} / {col1_bg}"

    def test_table2_has_row_seps_not_outer_border(self, page, markup_url):
        """Table 1 (+rowSeps, no +border): subsequent body rows have a top border, table has none."""
        goto_slide_by_title(page, markup_url, "Tables")
        data = _table_style_data(page, 1)
        assert _no_visible_border(data["table_border_top"]), \
            f"no +border flag ⇒ table should have no outer top border, got {data['table_border_top']}"
        second_row_cell = next(c for c in data["cells"] if c["row"] == 1 and c["col"] == 0)
        assert not _no_visible_border(second_row_cell["bt"]), \
            f"+rowSeps should add top border to row 1 cells, got {second_row_cell['bt']}"

    def test_checkerboard_thead_striped(self, page, markup_url):
        """In checkerboard mode, thead should also show a column-stripe pattern
        (not a uniform background band). Table 2 is the smallest checkerboard but
        has no thead; use the markup fixture's 3rd table which has no thead either,
        so we test with an explicitly inline case via the demo's truth table? Skip:
        the markup fixture's checkerboard table has no colHeaders. Instead verify
        via CSS rule presence: thead th:nth-child(odd/even) gets a col-stripe bg
        whenever both striped-rows and striped-cols classes are active.
        """
        # The markup fixture's checkerboard table (index 2) has no thead, so the
        # assertion is structural: the CSS file must contain a rule targeting
        # thead cells when both stripe classes are active.
        from pathlib import Path
        css_path = Path(__file__).parent / ".." / "_test" / "markup" / "lib" / "table.css"
        css = css_path.read_text()
        assert ".striped-rows.striped-cols thead th" in css, \
            "checkerboard mode should stripe thead cells by column"

    def test_table3_checkerboard(self, page, markup_url):
        """Table 2 (+stripedRows +stripedCols): strict 2-colour checker.
        Adjacent cells differ; diagonally adjacent cells match (period 2, not 4)."""
        goto_slide_by_title(page, markup_url, "Tables")
        data = _table_style_data(page, 2)
        cells = {(c["row"], c["col"]): c["bg"] for c in data["cells"]}
        # A 2×2 checker: each cell must differ from its row- and column-neighbour.
        assert cells[(0, 0)] != cells[(0, 1)], \
            f"(0,0) must differ from row-neighbour (0,1), got {cells[(0,0)]} == {cells[(0,1)]}"
        assert cells[(0, 0)] != cells[(1, 0)], \
            f"(0,0) must differ from col-neighbour (1,0), got {cells[(0,0)]} == {cells[(1,0)]}"
        # And — because it's a strict 2-colour pattern — diagonals match.
        assert cells[(0, 0)] == cells[(1, 1)], \
            f"(0,0) and diagonal (1,1) must match in a strict checker, got {cells[(0,0)]} vs {cells[(1,1)]}"
        assert cells[(0, 1)] == cells[(1, 0)], \
            f"(0,1) and diagonal (1,0) must match in a strict checker, got {cells[(0,1)]} vs {cells[(1,0)]}"
        # Only two distinct background values should appear.
        unique = set(cells.values())
        assert len(unique) == 2, \
            f"checker should use exactly 2 colours, got {len(unique)}: {unique}"

    def test_table4_cell_gap_padding(self, page, markup_url):
        """Table 3 ((cellGap := "0.6em 1.2em")): cells use the overridden padding."""
        goto_slide_by_title(page, markup_url, "Tables")
        data = _table_style_data(page, 3)
        cell = data["cells"][0]
        # 0.6em 1.2em at the slide's font-size — browser resolves ems to px, so assert the 2:1 ratio.
        parts = cell["padding"].split()
        # padding: "top right bottom left" or collapsed to 2 values → ["Vem", "Hem"]
        vals = [float(p.rstrip("px")) for p in parts if p.endswith("px")]
        assert len(vals) >= 2
        vert, horiz = vals[0], vals[1]
        assert horiz > vert, f"cellGap '0.6em 1.2em' ⇒ horizontal padding > vertical, got {cell['padding']}"
        assert abs(horiz / vert - 2.0) < 0.05, f"horizontal:vertical padding should be ~2:1, got {cell['padding']}"

    def test_row_seps_spans_thead_boundary(self, page, markup_url):
        """Table 4 (+colHeaders +rowSeps, no +headerSep): the row separator should
        also appear between the thead row and the first body row — not only
        between subsequent body rows."""
        goto_slide_by_title(page, markup_url, "Tables")
        data = _table_style_data(page, 4)
        # Row 1 is the first tbody row (row 0 is thead). Its top border
        # should be a visible (thin) separator even without +headerSep.
        first_body_cell = next(c for c in data["cells"] if c["row"] == 1 and c["col"] == 0)
        assert not _no_visible_border(first_body_cell["bt"]), \
            f"+rowSeps should add a separator between thead and first body row, got {first_body_cell['bt']}"
        # And it must be the *thin* sep (1px), not thick — because +headerSep is off.
        assert first_body_cell["bt"].split(" ")[0] == "1px", \
            f"without +headerSep the sep should be thin (1px), got {first_body_cell['bt']}"

    def test_col_seps_spans_row_header_boundary(self, page, markup_url):
        """Table 4 (+rowHeaders +colSeps, no +headerSep): the column separator
        should appear between the row-header column and the first data column."""
        goto_slide_by_title(page, markup_url, "Tables")
        data = _table_style_data(page, 4)
        # For every tbody row, the cell at col=1 (first data cell) should have
        # a thin left border separating it from the row-header column.
        body_col1 = [c for c in data["cells"] if c["row"] >= 1 and c["col"] == 1]
        assert body_col1, "expected body cells at col=1"
        for c in body_col1:
            assert not _no_visible_border(c["bl"]), \
                f"+colSeps should add a left border to cell after row-header, got {c['bl']} at row={c['row']}"
            assert c["bl"].split(" ")[0] == "1px", \
                f"without +headerSep the sep should be thin (1px), got {c['bl']}"

    def test_no_flags_means_no_cell_borders(self, page, markup_url):
        """Regression: cells without +rowSeps/+colSeps/+border must have no visible border.

        Reveal.js themes set 'border-bottom: 1px solid' on every <th>/<td>; our CSS resets it.
        Tables 2 and 3 have no separator/border flags, so all cell borders should be absent.
        """
        goto_slide_by_title(page, markup_url, "Tables")
        for table_idx in (2, 3):
            data = _table_style_data(page, table_idx)
            for c in data["cells"]:
                for side, val in (("top", c["bt"]), ("bottom", c["bb"]),
                                  ("left", c["bl"]), ("right", c["br"])):
                    assert _no_visible_border(val), (
                        f"table {table_idx} cell (row={c['row']},col={c['col']}) "
                        f"has unexpected {side} border: {val}"
                    )
