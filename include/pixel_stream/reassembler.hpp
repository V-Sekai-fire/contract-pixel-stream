// SPDX-License-Identifier: Apache-2.0 OR MIT
#pragma once

#include "pixel_stream/wire.hpp"

#include <cstdint>
#include <map>
#include <optional>
#include <vector>

namespace pixel_stream {

struct Frame {
	std::uint32_t frame_seq = 0;
	std::uint32_t echoed_input_seq = 0;
	std::vector<std::uint8_t> payload;
};

// Mirrors PixelStream/Reassembly.lean. The Lean model proves monotone emit, no
// partial presentation and a bounded buffer; vectors/corpus.txt binds this code
// to that model.
class Reassembler {
public:
	explicit Reassembler(std::size_t capacity) :
			capacity_(capacity) {}

	std::optional<Frame> step(const FragmentHeader &h, const std::uint8_t *payload) {
		if (!header_well_formed(h)) {
			return std::nullopt;
		}
		if (has_emitted_ && h.frame_seq <= last_emitted_) {
			return std::nullopt;
		}

		Pending &p = pending_[h.frame_seq];
		if (p.frag_count == 0) {
			p.frag_count = h.frag_count;
			p.echoed_input_seq = h.echoed_input_seq;
		}
		p.slots.emplace(h.frag_index,
				std::vector<std::uint8_t>(payload, payload + h.payload_bytes));

		if (p.slots.size() != p.frag_count) {
			evict_oldest();
			return std::nullopt;
		}

		Frame out;
		out.frame_seq = h.frame_seq;
		out.echoed_input_seq = p.echoed_input_seq;
		for (const auto &slot : p.slots) {
			out.payload.insert(out.payload.end(), slot.second.begin(), slot.second.end());
		}

		last_emitted_ = h.frame_seq;
		has_emitted_ = true;
		pending_.erase(pending_.begin(), pending_.upper_bound(h.frame_seq));
		return out;
	}

private:
	struct Pending {
		std::uint16_t frag_count = 0;
		std::uint32_t echoed_input_seq = 0;
		std::map<std::uint16_t, std::vector<std::uint8_t>> slots;
	};

	void evict_oldest() {
		while (pending_.size() > capacity_) {
			pending_.erase(pending_.begin());
		}
	}

	std::size_t capacity_;
	std::uint32_t last_emitted_ = 0;
	bool has_emitted_ = false;
	std::map<std::uint32_t, Pending> pending_;
};

} // namespace pixel_stream
