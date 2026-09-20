// SPDX-License-Identifier: Apache-2.0 OR MIT

#include "pixel_stream/reassembler.hpp"

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct Expect {
	std::uint32_t frame_seq;
	std::uint32_t echoed_input_seq;
	std::vector<std::uint8_t> payload;
};

struct Trace {
	std::string name;
	std::size_t capacity = 0;
	std::vector<pixel_stream::FragmentHeader> headers;
	std::vector<std::vector<std::uint8_t>> payloads;
	std::vector<Expect> expect;
};

std::vector<std::uint8_t> parse_payload(const std::string &tok) {
	std::vector<std::uint8_t> out;
	if (tok == "-") {
		return out;
	}
	std::string cur;
	for (char c : tok) {
		if (c == '.') {
			if (!cur.empty()) {
				out.push_back(static_cast<std::uint8_t>(std::stoi(cur)));
			}
			cur.clear();
		} else {
			cur.push_back(c);
		}
	}
	return out;
}

std::vector<Trace> load(const std::string &path) {
	std::vector<Trace> traces;
	std::ifstream in(path);
	std::string line;
	Trace cur;
	bool open = false;
	while (std::getline(in, line)) {
		std::istringstream ls(line);
		std::string kind;
		ls >> kind;
		if (kind == "TRACE") {
			cur = Trace{};
			ls >> cur.name >> cur.capacity;
			open = true;
		} else if (kind == "FRAG" && open) {
			unsigned seq, idx, cnt, echo;
			std::string pay;
			ls >> seq >> idx >> cnt >> echo >> pay;
			std::vector<std::uint8_t> bytes = parse_payload(pay);
			pixel_stream::FragmentHeader h{};
			h.version = pixel_stream::kWireVersion;
			h.frame_seq = seq;
			h.frag_index = static_cast<std::uint16_t>(idx);
			h.frag_count = static_cast<std::uint16_t>(cnt);
			h.echoed_input_seq = echo;
			h.payload_bytes = static_cast<std::uint16_t>(bytes.size());
			cur.headers.push_back(h);
			cur.payloads.push_back(bytes);
		} else if (kind == "EXPECT" && open) {
			unsigned seq, echo;
			std::string pay;
			ls >> seq >> echo >> pay;
			cur.expect.push_back(Expect{ seq, echo, parse_payload(pay) });
		} else if (kind == "END" && open) {
			traces.push_back(cur);
			open = false;
		}
	}
	return traces;
}

// The control: emits on the first fragment it sees, which is the defect a
// hand-written reassembler ships. The corpus must refuse it.
class BrokenReassembler {
public:
	explicit BrokenReassembler(std::size_t) {}
	std::optional<pixel_stream::Frame> step(const pixel_stream::FragmentHeader &h,
			const std::uint8_t *payload) {
		pixel_stream::Frame f;
		f.frame_seq = h.frame_seq;
		f.echoed_input_seq = h.echoed_input_seq;
		f.payload.assign(payload, payload + h.payload_bytes);
		return f;
	}
};

template <typename R>
bool matches(const Trace &t) {
	R r(t.capacity);
	std::vector<pixel_stream::Frame> got;
	for (std::size_t i = 0; i < t.headers.size(); ++i) {
		const std::uint8_t *p = t.payloads[i].empty() ? nullptr : t.payloads[i].data();
		auto out = r.step(t.headers[i], p);
		if (out.has_value()) {
			got.push_back(*out);
		}
	}
	if (got.size() != t.expect.size()) {
		return false;
	}
	for (std::size_t i = 0; i < got.size(); ++i) {
		if (got[i].frame_seq != t.expect[i].frame_seq ||
				got[i].echoed_input_seq != t.expect[i].echoed_input_seq ||
				got[i].payload != t.expect[i].payload) {
			return false;
		}
	}
	return true;
}

} // namespace

int main(int argc, char **argv) {
	const std::string path = argc > 1 ? argv[1] : "vectors/corpus.txt";
	std::vector<Trace> traces = load(path);

	// A corpus that failed to load must FAIL, not pass quietly: a silent skip
	// reads exactly like a pass.
	if (traces.empty()) {
		std::printf("FAIL: no traces loaded from %s\n", path.c_str());
		return 1;
	}

	int failed = 0;
	for (const Trace &t : traces) {
		const bool ok = matches<pixel_stream::Reassembler>(t);
		std::printf("  %-20s %s\n", t.name.c_str(), ok ? "ok" : "FAIL");
		if (!ok) {
			++failed;
		}
	}

	int refused = 0;
	for (const Trace &t : traces) {
		if (!matches<BrokenReassembler>(t)) {
			++refused;
		}
	}
	std::printf("\n%zu traces, %d failed; control refused by %d of %zu\n",
			traces.size(), failed, refused, traces.size());

	if (refused == 0) {
		std::printf("FAIL: the broken control passed every trace, so this gate is decoration\n");
		return 1;
	}
	return failed == 0 ? 0 : 1;
}
