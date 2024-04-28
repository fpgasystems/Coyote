"""
Custom docutils writer for markdown.
"""
from docutils import frontend, writers

from sphinx_markdown_builder.translator import MarkdownTranslator


class MarkdownWriter(writers.Writer):
    supported = ("markdown",)
    """Formats this writer supports."""

    output = None
    """Final translated form of `document`."""

    # Add configuration settings for additional Markdown flavours here.
    settings_spec = (
        "Markdown writer options",
        None,
        (
            (
                "Extended Markdown syntax.",
                ["--extended-markdown"],
                {
                    "default": 0,
                    "action": "store_true",
                    "validator": frontend.validate_boolean,
                },
            ),
            (
                "Strict Markdown syntax. Default: true",
                ["--strict-markdown"],
                {
                    "default": 1,
                    "action": "store_true",
                    "validator": frontend.validate_boolean,
                },
            ),
        ),
    )

    translator_class = MarkdownTranslator

    def __init__(self, builder=None):
        super().__init__()
        self.builder = builder

    def translate(self):
        visitor = self.builder.create_translator(self.document, self.builder)
        self.document.walkabout(visitor)
        self.output = visitor.astext()
