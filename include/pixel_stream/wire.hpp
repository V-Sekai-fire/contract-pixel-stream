// SPDX-License-Identifier: Apache-2.0 OR MIT
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace pixel_stream {

// A QUIC datagram that fits the common 1280-byte IPv6 minimum MTU after QUIC
// and WebTransport overhead. Fragmenting to this avoids IP fragmentation.
inline constexpr std::size_t kDatagramBytes = 1200;

inline constexpr char kServiceName[] = "weft/pixel_stream/frame";
inline constexpr std::uint32_t kWireVersion = 1;

#pragma pack(push, 1)
struct FragmentHeader {
	std::uint32_t version;
	std::uint32_t frame_seq;
	std::uint16_t frag_index;
	std::uint16_t frag_count;
	std::uint32_t echoed_input_seq;
	std::uint16_t payload_bytes;
};
#pragma pack(pop)

// iceoryx2 refuses to connect two services that disagree on name, type, size
// or alignment, so the size is pinned here rather than left to the compiler.
static_assert(sizeof(FragmentHeader) == 18, "FragmentHeader must stay 18 bytes");
static_assert(alignof(FragmentHeader) == 1, "FragmentHeader must stay packed");

inline constexpr std::size_t kMaxPayloadBytes = kDatagramBytes - sizeof(FragmentHeader);

inline bool header_well_formed(const FragmentHeader &h) {
	return h.version == kWireVersion && h.frag_count > 0 &&
			h.frag_index < h.frag_count && h.payload_bytes <= kMaxPayloadBytes;
}

inline std::size_t fragment_count_for(std::size_t frame_bytes) {
	return frame_bytes == 0 ? 1 : (frame_bytes + kMaxPayloadBytes - 1) / kMaxPayloadBytes;
}

inline std::size_t encode(const FragmentHeader &h, const std::uint8_t *payload,
		std::uint8_t *out, std::size_t out_bytes) {
	const std::size_t total = sizeof(FragmentHeader) + h.payload_bytes;
	if (out_bytes < total) {
		return 0;
	}
	std::memcpy(out, &h, sizeof(FragmentHeader));
	if (h.payload_bytes > 0) {
		std::memcpy(out + sizeof(FragmentHeader), payload, h.payload_bytes);
	}
	return total;
}

inline bool decode(const std::uint8_t *in, std::size_t in_bytes, FragmentHeader &h,
		const std::uint8_t *&payload) {
	if (in_bytes < sizeof(FragmentHeader)) {
		return false;
	}
	std::memcpy(&h, in, sizeof(FragmentHeader));
	if (!header_well_formed(h) || in_bytes < sizeof(FragmentHeader) + h.payload_bytes) {
		return false;
	}
	payload = in + sizeof(FragmentHeader);
	return true;
}

} // namespace pixel_stream
