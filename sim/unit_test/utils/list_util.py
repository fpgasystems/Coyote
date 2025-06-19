from typing import List, Any


def split_list(elements, chunk_size):
    return [elements[i : i + chunk_size] for i in range(0, len(elements), chunk_size)]


def split_into_batches(list, n_batches):
    """
    Splits the given list into n_batches as evenly as possible.
    E.g. if n = len(list) % n_batches and n != 0, the remainder will
        be distributed among the first n batches.
    """
    assert len(list) >= n_batches, (
        f"Cannot split list with {len(list)} elements into {n_batches} batches"
    )

    # The sizes of the individual batches
    elem_per_batch = len(list) // n_batches
    sizes = [elem_per_batch for _ in range(0, n_batches)]

    # Add the remainder to the first batches, if there is any
    remainder = len(list) % n_batches
    for i in range(0, remainder):
        sizes[i] += 1

    # Get the batches!
    index = 0
    batches = []
    for size in sizes:
        batches.append(list[index : index + size])
        index += size

    return batches


def flatten_list(xss: List[List[Any]]) -> List[Any]:
    return [x for xs in xss for x in xs]
