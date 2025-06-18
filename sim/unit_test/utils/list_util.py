from typing import List, Any

def split_list(elements, chunk_size):
    return [elements[i:i + chunk_size] for i in range(0, len(elements), chunk_size)]

def split_into_batches(list, n_batches):
    # Source code from: https://stackoverflow.com/a/72510715/5589776
    k, m = divmod(len(list), n_batches)
    return (list[i*k+min(i, m):(i+1)*k+min(i+1, m)] for i in range(n_batches))

def flatten_list(xss: List[List[Any]]) -> List[Any]:
    return [x for xs in xss for x in xs]