"""
A Sphinx extension to add markdown generation support.
"""
from sphinx_markdown_builder.builder import MarkdownBuilder

__version__ = "0.6.6"
__docformat__ = "reStructuredText"


def setup(app):
    app.add_builder(MarkdownBuilder)
    app.add_config_value("markdown_http_base", "", False)
    app.add_config_value("markdown_uri_doc_suffix", ".md", False)
    app.add_config_value("markdown_anchor_sections", False, False)
    app.add_config_value("markdown_anchor_signatures", False, False)
    app.add_config_value("markdown_docinfo", False, False)
