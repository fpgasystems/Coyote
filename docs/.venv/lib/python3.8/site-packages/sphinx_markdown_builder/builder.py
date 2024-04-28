"""
Custom docutils builder for markdown.
"""
import os
from contextlib import contextmanager
from typing import Set

from docutils import nodes
from docutils.io import StringOutput
from sphinx.application import Sphinx
from sphinx.builders import Builder
from sphinx.environment import BuildEnvironment
from sphinx.locale import __
from sphinx.util import logging
from sphinx.util.osutil import ensuredir, os_path

from sphinx_markdown_builder.translator import MarkdownTranslator
from sphinx_markdown_builder.writer import MarkdownWriter

logger = logging.getLogger(__name__)


@contextmanager
def io_handler(file_path: str, log_error=True):
    try:
        yield
    except (IOError, OSError) as err:
        if log_error:
            logger.warning(__("error accessing file %s: %s"), file_path, err)


def get_mod_time_if_exists(file_path, log_error=True):
    with io_handler(file_path, log_error):
        return os.path.getmtime(file_path)


class MarkdownBuilder(Builder):
    name = "markdown"
    format = "markdown"
    epilog = __("The markdown files are in %(outdir)s.")

    allow_parallel = True
    default_translator_class = MarkdownTranslator

    out_suffix = ".md"

    def __init__(self, app: Sphinx, env: BuildEnvironment = None):
        super().__init__(app, env)
        self.writer = None
        self.sec_numbers = None
        self.current_doc_name = None

    def init(self):
        self.sec_numbers = {}

    def _get_source_mtime(self, doc_name: str):
        source_name = self.env.doc2path(doc_name)
        return get_mod_time_if_exists(source_name)

    def _get_target_mtime(self, doc_name: str):
        target_name = os.path.join(self.outdir, doc_name + self.out_suffix)
        return get_mod_time_if_exists(target_name, log_error=False)

    def get_outdated_docs(self):
        for doc_name in self.env.found_docs:
            if doc_name not in self.env.all_docs:
                yield doc_name
                continue

            source_mtime = self._get_source_mtime(doc_name)
            target_mtime = self._get_target_mtime(doc_name)
            if source_mtime is None or target_mtime is None or source_mtime > target_mtime:
                yield doc_name

    def get_target_uri(self, docname: str, typ: str = None):
        """
        Returns the target file name.
        By default, we link to the currently generated markdown files.
        But, we also support linking to external document (e.g., an html web page).
        """
        return f"{docname}{self.config.markdown_uri_doc_suffix}"

    def prepare_writing(self, docnames: Set[str]):
        self.writer = MarkdownWriter(self)

    def write_doc(self, docname: str, doctree: nodes.document):
        self.current_doc_name = docname
        self.sec_numbers = self.env.toc_secnumbers.get(docname, {})
        destination = StringOutput(encoding="utf-8")
        self.writer.write(doctree, destination)
        out_filename = os.path.join(self.outdir, f"{os_path(docname)}{self.out_suffix}")
        ensuredir(os.path.dirname(out_filename))

        with io_handler(out_filename):
            with open(out_filename, "w", encoding="utf-8") as file:
                file.write(self.writer.output)
