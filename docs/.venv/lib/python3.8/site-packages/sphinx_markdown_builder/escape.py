"""
Escaping text for markdown and html.

Characters that should be escaped in Markdown:
----------------------------------------------
Emphasis chars: * and _
  Emphasis char prefix/postfix should have a non-space char to its right/left.
  _ prefix/postfix must have a space char to its left/right (or beginning/end of the text).
  We cannot make the destination between prefix/postfix in regular expression, so we will enforce both for all.
Quote/Title: > and #
  Should only precede by space chars in the line.
Block char: `
  One ` only requires not to have double line break in between
  Double `` seems to be ignored
  Three ``` must be at the beginning of the line
Title: ----
  A line that only have - or =
  No spaces between them
Horizontal line: ----
  A line that only have 3 consecutive -, _, or * or more.
  Precedes an empty line or beginng of text.
Links: [text](link)
Images: ![alt](link)
Lists: +, -, *, 1.
Tables: |
Anything starting with 4 spaces is considered a block.
  Should add force spaces (\\ ) to avoid it.
Escape char: \
  Should be followed by:
  Character Name
  \\        backslash
  `         backtick (see also escaping backticks in code)
  *         asterisk
  _         underscore
  { }       curly braces
  [ ]       brackets
  < >       angle brackets
  ( )       parentheses
  #         pound sign
  +         plus sign
  -         minus sign (hyphen)
  .         dot
  !         exclamation mark
  |         pipe (see also escaping pipe in tables)
"""
import re

ESCAPE_RE = re.compile(r"([\\*`]|(?:^|(?<=\s|_))_)", re.M)


def escape_markdown_chars(txt: str):
    """Escape (some) characters with special meaning for Markdown"""
    return ESCAPE_RE.sub(r"\\\1", txt)


def escape_html_quote(value: str):
    return value.replace('"', "&quot;")
