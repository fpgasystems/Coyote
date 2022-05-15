#ifndef STREAM_HPP
#define STREAM_HPP

#include <hls_stream.h>
#include <ap_int.h>
#include "bit_utils.hpp"

#include <utility>
#include <type_traits>

//===========================================================================
// Flit structs carrying user data and batch boundary info (`last`)

// Flit Base
struct flit_t {
	bool  last;
	flit_t(bool l = false) : last(l) {}
};

// Flit with User Data
template<typename TV>
struct flit_v_t : public flit_t {
	TV	val;
	flit_v_t() : flit_t(), val() {}
	flit_v_t(bool l, TV const &v) : flit_t(l), val(v) {}
};

// Flit with User Key-Value Pair
template<typename TK, typename TV>
struct flit_kv_t : public flit_v_t<TV> {
	TK	key;
	flit_kv_t() : flit_v_t<TV>(), key() {}
	flit_kv_t(bool l, TK const &k, TV const &v) : flit_v_t<TV>(l, v), key(k) {}
};

//===========================================================================
// Lightweight plug-in member accessor functors.

/**
 * DevNull  f;
 * f(<any args>...) is assignable from any expression.
 */
struct DevNull {
	struct Sink {
		template<typename T>
		void operator=(T&& rhs) const {}
	};
	template<typename... Args>
	constexpr Sink operator()(Args&&... args) const { return  Sink(); }
};

/**
 * Const<int> f(1);
 * f(arg0, arg1, ...) returns 1
 */
template<typename T>
class Const {
	T const	m_val;
public:
	Const(T const& val) : m_val(val) {}
public:
	template<typename... Args>
	constexpr T const& operator()(Args&&...) const noexcept { return  m_val; }
};

/**
 * Arg<i>  f;
 * f(arg0, arg1, ...) returns arg_i
 * Maintains references except for rvalue refs, which are reduced to prvalues.
 */
template<unsigned i>
struct Arg {
	template<typename A, typename... Args>
	constexpr auto operator()(A&& a, Args&&... args) const noexcept
	 -> decltype(Arg<i-1>()(std::forward<Args>(args)...)) {
		return  Arg<i-1>()(std::forward<Args>(args)...);
	}
};
template<>
struct Arg<0> {
	template<typename T> struct remove_rvref      { using type = T; };
	template<typename T> struct remove_rvref<T&&> { using type = T; };
	template<typename A, typename... Args>
	constexpr auto operator()(A&& a, Args&&... args) const noexcept
	 -> typename remove_rvref<A>::type {
		return  a;
	}
};

// Flit Inspection Functors
#define BUILD_MEMBER_ACCESSOR(NAME, MEMBER) \
struct NAME { \
	template<typename T> \
	auto operator()(T& x) const noexcept \
	 -> typename std::add_lvalue_reference<decltype(x.MEMBER)>::type { \
		return  x.MEMBER; \
	} \
	template<typename T> \
	auto operator()(T const& x) const noexcept \
	 -> typename std::add_lvalue_reference<typename std::add_const<decltype(x.MEMBER)>::type>::type { \
		return  x.MEMBER; \
	} \
	template<typename T> \
	auto operator()(T&& x) const noexcept \
	 -> decltype(x.MEMBER) { \
		return  x.MEMBER; \
	} \
};
BUILD_MEMBER_ACCESSOR(MemberLast, last)
BUILD_MEMBER_ACCESSOR(MemberKey,  key)
BUILD_MEMBER_ACCESSOR(MemberVal,  val)
#undef BUILD_MEMBER_ACCESSOR

//===========================================================================
// Stateless Stream Manipulation Stages
template<
	typename F = Arg<0>,
	typename TI,
	typename TO
>
void stage_guarded(
	hls::stream<TI> &src,
	hls::stream<TO> &dst,
	F &&f = F()
) {
#pragma HLS inline off
#pragma HLS pipeline II=1
	TI x;
	if(src.read_nb(x))	dst.write(f(x));
}

template<
	typename F = Arg<0>,	// f(TI, 0:N-1) -> TO
	typename TI,
	typename TO,
	unsigned N
>
void stream_split(
	hls::stream<TI>  &src,
	hls::stream<TO> (&dst)[N],
	F &&f = F()
) {
#pragma HLS inline off
#pragma HLS pipeline II=1
	TI x;
	if(src.read_nb(x)) {
		for(unsigned i = 0; i < N; i++) {
#pragma HLS unroll
			dst[i].write(f(x, i));
		}
	}
} // stream_split()

/**
 * Folds N source streams into one destination stream output by output
 * yielding f(...f(f(null_val, src[0].read()), src[1].read()), ... ).
 */
template<
	typename F,	// f(TO, TI) -> TO
	typename TI,
	typename TO,
	unsigned N
>
void stream_fold(
	hls::stream<TI> (&src)[N],
	hls::stream<TO>  &dst,
	F&& f
) {
#pragma HLS inline off
#pragma HLS pipeline II=1
	ap_uint<N>	empty;
	for(unsigned i = 0; i < N; i++) {
#pragma HLS unroll
		empty[i] = src[i].empty();
	}

	if(empty == 0) {
		TO y = 0;
		for(unsigned i = 0; i < N; i++) {
#pragma HLS unroll
			y = f(y, src[i].read());
		}
		dst.write(y);
	}

} // stream_fold()

//===========================================================================
/**
 * Stream concatenation of N streams 0, .., N-1 switching to the next
 * when seeing T.last.
 */
template<unsigned N>
class StreamConcatenator {
	ap_uint<btl::clog2<N>::value>	idx = 0;

public:
	template<
		typename TXL = MemberLast,
		typename F   = Arg<0>,
		typename TI,
		typename TO
	>
	void concat(
		hls::stream<TI> (&src)[N],
		hls::stream<TO>  &dst,
		TXL &&txl = TXL(),
		F   &&f   = F()
	) {
#pragma HLS inline off
#pragma HLS pipeline II=1
		TI x;
		if(src[idx].read_nb(x)) {
			if(txl(x)) {
				if(idx == N-1) idx = 0; else idx++;
			}
			dst.write(f(x));
		}
	}

}; // class StreamConcatenator

//---------------------------------------------------------------------------
// Trivial Specialization for N=1
template<>
class StreamConcatenator<1> {
public:
	template<
		typename TXL = MemberLast,
		typename F   = Arg<0>,
		typename TI,
		typename TO
	>
	void concat(
		hls::stream<TI> (&src)[1],
		hls::stream<TO>  &dst,
		TXL &&txl = TXL(),
		F   &&f   = F()
	) {
#pragma HLS inline off
#pragma HLS pipeline II=1
		TI x;
		if(src[0].read_nb(x))	dst.write(f(x));
	}
}; // class StreamConcatenator

template<>
class StreamConcatenator<0> {};

//===========================================================================
template<unsigned N>
class StreamInterleaver {
	ap_uint<btl::clog2<N>::value>	idx = 0;

public:
	/**
	 * Round-robin through source streams 0,..N-1 forwarding each
	 * value x to the destination stream after manipulation by f(x, idx).
	 * The default manipulation passes the value unchanged.
	 */
	template<
		typename F = Arg<0>,
		typename TI,
		typename TO
	>
	void interleave(
		hls::stream<TI> (&src)[N],
		hls::stream<TO>  &dst,
		F &&f = F()
	) {
#pragma HLS inline off
#pragma HLS pipeline II=1
		TI x;
		if(src[idx].read_nb(x)) {
			dst.write(f(x, idx));
			if(idx == N-1)	idx = 0; else idx++;
		}
	}

}; // class StreamInterleaver

//---------------------------------------------------------------------------
// Trivial Specialization for N=1
template<>
class StreamInterleaver<1> {
public:
	template<
		typename F = Arg<0>,
		typename TI,
		typename TO
	>
	void interleave(
		hls::stream<TI> (&src)[1],
		hls::stream<TO>  &dst,
		F &&f = F()
	) {
#pragma HLS inline off
#pragma HLS pipeline II=1
		TI x;
		if(src[0].read_nb(x)) {
			dst.write(f(x, 0));
		}
	}

}; // class StreamInterleaver

template<>
class StreamInterleaver<0> {};

#endif
