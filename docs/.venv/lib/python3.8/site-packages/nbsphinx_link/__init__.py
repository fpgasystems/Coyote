"""A sphinx extension for including notebook files from outside sphinx source root.

Usage:
- Install the package.
- Add 'nbsphinx_link' to extensions in Sphinx config 'conf.py'
- Add a file with the '.nblink' extension where you want them included.

The .nblink file is a JSON file with the following structure:

{
    "path": "relative/path/to/notebook"
}


Optionally the "extra-media" key can be added, if your notebook includes
any media, i.e. images. The value needs to be an array of strings,
which are paths to the media files or directories.

Further keys might be added in the future.
"""

import json
import os
import shutil

from docutils import io, nodes, utils
from docutils.utils.error_reporting import SafeString, ErrorString
import docutils  # noqa: F401
from nbsphinx import NotebookParser, NotebookError, _ipynbversion
import nbformat
from sphinx.util.logging import getLogger

from ._version import __version__


def register_dependency(file_path, document):
    """
    Registers files as dependency, so sphinx rebuilds the docs
    when they changed.

    Parameters
    ----------
    file_path : str
        [description]
    document: docutils.nodes.document
        Parsed document instance.
    """
    document.settings.record_dependencies.add(file_path)
    document.settings.env.note_dependency(file_path)


def copy_file(src, dest, document):
    """
    Copies a singe file from ``src`` to ``dest``.

    Parameters
    ----------
    src : str
        Path to the source file.
    dest : str
        Path to the destination file or directory.
    document: docutils.nodes.document
        Parsed document instance.
    """
    logger = getLogger(__name__)
    try:
        shutil.copy(src, dest)
        register_dependency(src, document)
    except (OSError) as e:
        logger.warning(
            "The the file {} couldn't be copied. "
            "Error:\n {}".format(src, e)
        )


def copy_and_register_files(src, dest, document):
    """
    Copies a directory or file from the path ``src`` to ``dest``
    and registers all files as dependency,
    so sphinx rebuilds the docs when they changed.

    Parameters
    ----------
    src : str
        Path to the source directory or file
    dest : str
        Path to the destination directory or file
    document: docutils.nodes.document
        Parsed document instance.
    """
    if os.path.isdir(src):
        for root, _, filenames in os.walk(src):
            dst_root = os.path.join(dest, os.path.relpath(root, src))
            if filenames and not os.path.exists(dst_root):
                os.makedirs(dst_root)
            for filename in filenames:
                src_path = os.path.abspath(os.path.join(root, filename))
                copy_file(src_path, dst_root, document)
    else:
        copy_file(src, dest, document)


def collect_extra_media(extra_media, source_file, nb_path, document):
    """
    Collects extra media defined in the .nblink file,  with the key
    'extra-media'. The extra media (i.e. images) need to be copied
    in order for nbsphinx to properly render the notebooks, since
    nbsphinx assumes that the files are relative to the .nblink.

    Parameters
    ----------
    extra_media : list
        Paths to directories and/or files with extra media.
    source_file : str
        Path to the .nblink file.
    nb_path : str
        Path to the notebook defined in the .nblink file , with the key 'path'.
    document: docutils.nodes.document
        Parsed document instance.

    """
    any_dirs = False
    logger = getLogger(__name__)
    source_dir = os.path.dirname(source_file)
    if not isinstance(extra_media, list):
        logger.warning(
            'The "extra-media", defined in {} needs to be a list of paths. '
            'The current value is:\n{}'.format(source_file, extra_media)
        )
    for extract_media_path in extra_media:
        if os.path.isabs(extract_media_path):
            src_path = extract_media_path
        else:
            extract_media_relpath = os.path.join(
                source_dir, extract_media_path
            )
            src_path = os.path.normpath(
                os.path.join(source_dir, extract_media_relpath)
            )

        dest_path = utils.relative_path(nb_path, src_path)
        dest_path = os.path.normpath(os.path.join(source_dir, dest_path))
        if os.path.exists(src_path):
            any_dirs = any_dirs or os.path.isdir(src_path)
            copy_and_register_files(src_path, dest_path, document)
        else:
            logger.warning(
                'The path "{}", defined in {} "extra-media", '
                'isn\'t a valid path.'.format(
                    extract_media_path, source_file
                )
            )
        if any_dirs:
            document.settings.env.note_reread()


class LinkedNotebookParser(NotebookParser):
    """A parser for .nblink files.

    The parser will replace the link file with the output from
    nbsphinx on the linked notebook. It will also add the linked
    file as a dependency, so that sphinx will take it into account
    when figuring out whether it should be rebuilt.

    The .nblink file is a JSON file with the following structure:

    {
        "path": "relative/path/to/notebook"
    }

    Optionally the "extra-media" key can be added, if your notebook includes
    any media, i.e. images. The value needs to be an array of strings,
    which are paths to the media files or directories.

    Further keys might be added in the future.
    """

    supported = 'linked_jupyter_notebook',

    def parse(self, inputstring, document):
        """Parse the nblink file.

        Adds the linked file as a dependency, read the file, and
        pass the content to the nbshpinx.NotebookParser.
        """
        link = json.loads(inputstring)
        env = document.settings.env
        source_dir = os.path.dirname(env.doc2path(env.docname))

        abs_path = os.path.normpath(os.path.join(source_dir, link['path']))
        path = utils.relative_path(None, abs_path)
        path = nodes.reprunicode(path)

        extra_media = link.get('extra-media', None)
        if extra_media:
            source_file = env.doc2path(env.docname)
            collect_extra_media(extra_media, source_file, path, document)

        register_dependency(path, document)

        target_root = env.config.nbsphinx_link_target_root
        target = utils.relative_path(target_root, abs_path)
        target = nodes.reprunicode(target).replace(os.path.sep, '/')
        env.metadata[env.docname]['nbsphinx-link-target'] = target

        # Copy parser from nbsphinx for our cutom format
        try:
            formats = env.config.nbsphinx_custom_formats
        except AttributeError:
            pass
        else:
            formats.setdefault(
                '.nblink',
                lambda s: nbformat.reads(s, as_version=_ipynbversion))

        try:
            include_file = io.FileInput(source_path=path, encoding='utf8')
        except UnicodeEncodeError as error:
            raise NotebookError(u'Problems with linked notebook "%s" path:\n'
                                'Cannot encode input file path "%s" '
                                '(wrong locale?).' %
                                (env.docname, SafeString(path)))
        except IOError as error:
            raise NotebookError(u'Problems with linked notebook "%s" path:\n%s.' %
                                (env.docname, ErrorString(error)))

        try:
            rawtext = include_file.read()
        except UnicodeError as error:
            raise NotebookError(u'Problem with linked notebook "%s":\n%s' %
                                (env.docname, ErrorString(error)))
        return super(LinkedNotebookParser, self).parse(rawtext, document)


def setup(app):
    """Initialize Sphinx extension."""
    app.setup_extension('nbsphinx')
    app.add_source_suffix('.nblink', 'linked_jupyter_notebook')
    app.add_source_parser(LinkedNotebookParser)
    app.add_config_value('nbsphinx_link_target_root', None, rebuild='env')

    return {'version': __version__, 'parallel_read_safe': True}
