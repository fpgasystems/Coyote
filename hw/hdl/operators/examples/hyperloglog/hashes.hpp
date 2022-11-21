#ifndef HASHES_HPP
#define HASHES_HPP

#include <ap_int.h>
#include <cstdint>

//---------------------------------------------------------------------------
// ConcatHash
//	Allows to assemble a wider hash function by concatenating sub hashes.
template<typename... Hashes>
class ConcatHash;

template<typename Hash>
class ConcatHash<Hash> : public Hash {
	Hash	hash;
public:
	ConcatHash() {}
	~ConcatHash() {}
public:
	template<typename T>
	auto operator()(T val) const -> ap_uint<decltype(hash(val))::width> {
		return hash(val);
	}
};

template<typename Hash, typename... Tail>
class ConcatHash<Hash, Tail...> {
	Hash				hash;
	ConcatHash<Tail...>	tail;
public:
	ConcatHash() {}
	~ConcatHash() {}
public:
	template<typename T>
	auto operator()(T val) const -> ap_uint<decltype(hash(val))::width + decltype(tail(val))::width> {
		return (hash(val), tail(val));
	}
};

//---------------------------------------------------------------------------
// Murmur3_128
template<uint64_t SEED>
class Murmur3_128 {
	static uint64_t const  c1 = 0x87c37b91114253d5;
	static uint64_t const  c2 = 0x4cf5ad432745937f;
	static uint64_t const  c3 = 0xff51afd7ed558ccd;
	static uint64_t const  c4 = 0xc4ceb9fe1a85ec53;

public:
	Murmur3_128() {}
	~Murmur3_128() {}

public:
	ap_uint<128> operator()(ap_uint<32> data) const {
		ap_uint<64> const  len = 4;
		ap_uint<64> k1 = data;

		ap_uint<64> h1 = SEED;
		ap_uint<64> h2 = SEED;

		k1 *= c1;
		k1 = (k1 << 31) | (k1 >> (64 - 31));
		k1 *= c2;
		h1 ^= k1;

		h1 ^= len;
		h2 ^= len;

		h1 += h2;
		h2 += h1;

		h1 ^= h1 >> 33;
		h1 *= c3;
		h1 ^= h1 >> 33;
		h1 *= c4;
		h1 ^= h1 >> 33;

		h2 ^= h2 >> 33;
		h2 *= c3;
		h2 ^= h2 >> 33;
		h2 *= c4;
		h2 ^= h2 >> 33;

		h1 += h2;
		h2 += h1;

		return (h2, h1);
	}

}; // Murmur3_128

//	A truncated implementation of the 128-bit Murmur3 hash.
template<uint64_t SEED>
class Murmur3_64 {
	Murmur3_128<SEED>  hash;

public:
	Murmur3_64() {}
	~Murmur3_64() {}

public:
	ap_uint<64> operator()(ap_uint<32> data) const {
		return	hash(data);
	}

}; // Murmur3_64

#endif
