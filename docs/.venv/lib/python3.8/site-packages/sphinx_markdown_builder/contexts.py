"""
Custom context handlers for markdown.
"""
import re
import sys
import textwrap
import typing
from dataclasses import dataclass
from typing import Any, Callable, Dict, Generic, Iterator, List, Optional, Type, TypeVar, Union

from tabulate import tabulate

from sphinx_markdown_builder.escape import escape_html_quote


class UniqueString(str):
    pass


if sys.version_info >= (3, 8):
    Target = typing.Literal["body", "head"]
else:
    Target = str  # pragma: no cover

DEFAULT_TARGET = "body"
CONTENT_START = UniqueString("content start")
EOL = "\n"
SPACE = " "
SPACE_CHARS = re.compile(r"\s+")
LETTERS = re.compile(r"[a-z0-9]", re.I)
WRAP_REGEXP = re.compile(r"(\s*)(?=\S)([\s\S]+?)(?<=\S)(\s*)", re.M)
MULTI_LINE_BREAK = re.compile(r"(?<=\n)\n")


def is_content_start(value: str) -> bool:
    return isinstance(value, UniqueString) and value is CONTENT_START


def is_space(value: str) -> bool:
    return SPACE_CHARS.fullmatch(value) is not None


def is_eol(value: str) -> bool:
    return value == EOL


def is_letter(value: str) -> bool:
    return LETTERS.fullmatch(value) is not None


def replace_multi_line_break(value: str):
    return MULTI_LINE_BREAK.sub("<br/>\n", value)


@dataclass
class SubContextParams:
    prefix_eol: int = 0
    suffix_eol: int = 0
    target: Target = DEFAULT_TARGET


class ListMarker:
    def __init__(self, marker: Union[str, int]):
        self._marker = marker

    def inc(self):
        if isinstance(self._marker, int):
            self._marker += 1

    def __repr__(self):
        if isinstance(self._marker, int):
            return f"{self._marker}. "
        return self._marker


@dataclass(frozen=True)
class ContextStatus:
    escape_text: bool = True  # Whether to escape characters
    section_level: int = 0  # Current section heading level
    list_marker: Optional[ListMarker] = None  # Current list marker
    desc_type: Optional[str] = None  # Current descriptor type
    default_ref_internal: bool = False  # Current default for internal reference


class SubContext:
    def __init__(self, params=SubContextParams()):
        self.params: SubContextParams = params
        self.body: List[str] = []
        self.ensure_eol_count: int = 0

    @property
    def content(self) -> List[str]:
        return self.body

    def _iter_reverse_char(self) -> Iterator[str]:
        for value in reversed(self.content):
            yield from reversed(value)

        yield CONTENT_START

    def _count_missing_eol(self) -> int:
        """
        Count the number of EOL characters.
        Avoids adding EOL at the beginning of the content.
        Ignores spaces when traversing the content.
        """
        missing_count = self.ensure_eol_count
        for value in self._iter_reverse_char():
            if is_content_start(value):
                missing_count = 0
            if missing_count <= 0 or not is_space(value):
                break

            # This can only happen if the node's text had trailing EOL.
            # But docutils nodes are expected to be without.
            # So this validation is to avoid redundant EOLs if this behaviour changes in future releases.
            if is_eol(value):
                missing_count -= 1

        return max(0, missing_count)

    def ensure_eol(self, count: int = 1):
        """Ensures EOLs will be added before the next appended value"""
        self.ensure_eol_count = max(self.ensure_eol_count, count)

    def force_eol(self, count: int = 1):
        """Force adding the ensured EOLs"""
        self.ensure_eol(count)
        missing_eol = self._count_missing_eol()
        if missing_eol > 0:
            self.content.append(EOL * missing_eol)

    def add(self, value: str, prefix_eol: int = 0, suffix_eol: int = 0):
        """
        Add `value` to current context.

        Parameters
        ----------
        value : str
            String to add to output document
        prefix_eol: int
            Ensures prefix EOL
        suffix_eol: int
            Ensures suffix EOL
        """
        if not value:
            return

        self.force_eol(prefix_eol)
        self.content.append(value)
        self.ensure_eol_count = suffix_eol

    def make(self) -> str:
        """Generate the context's content"""
        return "".join(self.content)


class WrappedContext(SubContext):
    def __init__(
        self,
        prefix,
        suffix: Optional[str] = None,
        wrap_empty=False,
        params=SubContextParams(),
    ):  # pylint: disable=too-many-arguments
        super().__init__(params)
        self.prefix = prefix
        self.suffix = suffix if suffix is not None else prefix
        self.wrap_empty = wrap_empty

    def make(self):
        content = super().make()
        match = WRAP_REGEXP.fullmatch(content)
        if match is None:
            # The expression has no match only when there is no non-space character.
            if self.wrap_empty:
                return f"{self.prefix}{content}{self.suffix}"
            return content

        # We need to make sure the emphasis mark is near a non-space char,
        # but we want to preserve the existing spaces.
        prefix_space, text, suffix_space = match.groups()

        # Markdown requires italic/bold/etc... to have a space before it if the edge character is not a letter.
        if self.prefix in ["*", "_"] and not is_letter(text[0]) and len(prefix_space) == 0:
            prefix_space = SPACE
        return f"{prefix_space}{self.prefix}{text}{self.suffix}{suffix_space}"


class CommaSeparatedContext(SubContext):
    def __init__(self, sep: str = ", ", params=SubContextParams()):
        super().__init__(params)
        self.sep = sep
        self.parameters: List[List[str]] = []

        self.is_parameter = False

    def enter_parameter(self):
        self.is_parameter = True
        self.parameters.append([])

    def exit_parameter(self):
        self.is_parameter = False

    @property
    def content(self):
        if self.is_parameter:
            return self.parameters[-1]
        return super().content

    def make(self):
        ret = super().make()
        return ret + self.sep.join(["".join(item) for item in self.parameters])


class TableContext(SubContext):
    def __init__(self, params=SubContextParams()):
        super().__init__(params)
        self.body: List[List[List[str]]] = []
        self.headers: List[List[List[str]]] = []
        self.internal_context = SubContext()

        self.is_entry = False
        self.is_header = False
        self.is_body = False

    @property
    def active_output(self) -> List[List[List[str]]]:
        if self.is_header:
            return self.headers
        assert self.is_body
        return self.body

    @property
    def content(self):
        if self.is_entry:
            return self.active_output[-1][-1]
        return self.internal_context.content

    def enter_head(self):
        assert not self.is_header and not self.is_body
        self.is_header = True

    def exit_head(self):
        assert self.is_header and not self.is_body
        self.is_header = False

    def enter_body(self):
        assert not self.is_header and not self.is_body
        self.is_body = True

    def exit_body(self):
        assert self.is_body and not self.is_header
        self.is_body = False

    def enter_row(self):
        self.active_output.append([])

    def exit_row(self):
        pass

    def enter_entry(self):
        self.is_entry = True
        self.active_output[-1].append([])
        self.ensure_eol_count = 0

    def exit_entry(self):
        assert self.is_entry
        self.is_entry = False

    @staticmethod
    def make_row(row):
        return ["".join(entries).replace("\n", "<br/>") for entries in row]

    def make(self):
        ctx = SubContext()
        prefix = self.internal_context.make()
        if prefix:
            ctx.add(prefix)

        content = [*self.headers, *self.body]
        if len(content) > 0:
            headers = self.make_row(content[0])
            body = list(map(self.make_row, content[1:]))
            ctx.add(tabulate(body, headers=headers, tablefmt="github"), prefix_eol=2)
        return ctx.make()


class IndentContext(SubContext):
    def __init__(
        self,
        prefix,
        only_first=False,
        support_multi_line_break=False,
        empty=False,
        params=SubContextParams(1, 1),
    ):
        super().__init__(params)
        self.support_multi_line_break = support_multi_line_break
        self.empty = empty
        prefix = str(prefix)
        if only_first:
            self.prefix = " " * len(prefix)
            self.first_prefix = prefix
        else:
            self.prefix = prefix
            self.first_prefix = None

    def make(self):
        content = super().make()
        if self.support_multi_line_break:
            content = replace_multi_line_break(content)
        content = textwrap.indent(content, self.prefix, predicate=(lambda _: True) if self.empty else None)
        if self.first_prefix is None:
            return content
        return content.replace(self.prefix, self.first_prefix, 1)


class NoLineBreakContext(SubContext):
    def __init__(self, breaker=" ", params=SubContextParams()):
        super().__init__(params)
        self.breaker = breaker

    def make(self):
        return super().make().strip().replace(EOL, self.breaker)


class TitleContext(NoLineBreakContext):
    def __init__(self, level: int, params=SubContextParams(2, 2)):
        super().__init__("<br/>", params)
        self.level = level

    @property
    def section_prefix(self):
        return "#" * self.level

    def make(self):
        content = super().make()
        assert len(content) > 0, "Empty title"
        return f"{self.section_prefix} {content}"


class MetaContext(NoLineBreakContext):
    def __init__(self, name: str, params=SubContextParams(1, 1, target="head")):
        super().__init__("<br/>", params)
        assert name, "Empty meta name"
        self.name = name

    def make(self):
        content = super().make()
        if not content:
            return ""
        return f'<meta name="{escape_html_quote(self.name)}" content="{escape_html_quote(content)}"/>'


_ContextT = TypeVar("_ContextT", bound=SubContext)

Translator = Callable[[Any, Any], Dict[str, Any]]
DEFAULT_TRANSLATOR: Translator = lambda _node, _elem: {}


class PushContext(Generic[_ContextT]):  # pylint: disable=too-few-public-methods
    def __init__(
        self,
        ctx: Type[_ContextT],
        *args,
        translator: Translator = DEFAULT_TRANSLATOR,
        **kwargs,
    ):
        self.ctx = ctx
        self.translator = translator
        self.args = args
        self.kwargs = kwargs

    def create(self, node, element_key) -> _ContextT:
        kwargs = dict(self.kwargs)
        kwargs.update(self.translator(node, element_key))
        return self.ctx(*self.args, **kwargs)


ItalicContext = PushContext(WrappedContext, "*")  # _ is more restrictive
StrongContext = PushContext(WrappedContext, "**")  # _ is more restrictive
SubscriptContext = PushContext(WrappedContext, "<sub>", "</sub>")
DocInfoContext = PushContext(
    MetaContext,
    translator=lambda _node, elem: {"name": f"{elem}: "},
)
