#!/usr/bin/env python3
"""Regression test suite for sg-tightener.

Covers the CIDR collapsing algorithm, eligibility & port-merge logic,
the partition detector and severity-weighted risk score in the OU
report, and the input validation logic in sg_extend.

Any fix to the algorithm or parsing logic must keep this suite passing.

Run:
  python sg_tightener_test.py
"""

from __future__ import annotations

import ipaddress
import sys
import unittest

from sg_tightener import (
    collapse_ips_to_cidrs,
    merge_port_ranges,
    rule_is_eligible,
    _is_strict_rfc1918,
)
from sg_ou_report import (
    parse_partition_from_arn,
    compute_risk_score,
    classify_sg_rule,
)
from sg_extend import (
    parse_cidr,
    parse_port_spec,
    parse_group_id,
    proto_name,
    filter_flows,
    build_perms,
    perm_rule_count,
    _rule_count,
    _existing_nets_for,
    filter_existing,
)


class TestCollapseIpsToCidrs(unittest.TestCase):
    """Algorithm correctness — every IP covered, count respects budget."""

    def assert_all_covered(self, ips, cidrs):
        nets = [ipaddress.ip_network(c) for c in cidrs]
        for ip in ips:
            addr = ipaddress.ip_address(ip)
            self.assertTrue(
                any(addr in n for n in nets),
                f"IP {ip} not covered by {cidrs}",
            )

    def test_empty_input(self):
        self.assertEqual(collapse_ips_to_cidrs([]), [])

    def test_single_ip_produces_host_route(self):
        result = collapse_ips_to_cidrs(["10.0.10.5"])
        self.assertEqual(result, ["10.0.10.5/32"])

    def test_dense_subnet_collapses(self):
        ips = [f"10.0.10.{i}" for i in range(1, 30)]
        result = collapse_ips_to_cidrs(ips, max_rules=10)
        self.assert_all_covered(ips, result)
        self.assertLessEqual(len(result), 10)
        self.assertLess(len(result), len(ips), "dense subnet should collapse")

    def test_sparse_ips_stay_as_host_routes(self):
        ips = ["10.0.0.1", "10.5.0.1", "10.10.0.1"]
        result = collapse_ips_to_cidrs(ips, max_rules=10, tolerance=0.05)
        self.assert_all_covered(ips, result)
        # Each is far apart — under tight tolerance they remain narrow.
        for cidr in result:
            net = ipaddress.ip_network(cidr)
            self.assertLessEqual(net.num_addresses, 256)

    def test_force_fit_respects_budget(self):
        ips = [f"172.16.{i}.1" for i in range(0, 30)]
        result = collapse_ips_to_cidrs(ips, max_rules=5)
        self.assertLessEqual(
            len(result), 5,
            f"force-fit should reduce to <= 5, got {len(result)}: {result}",
        )
        self.assert_all_covered(ips, result)

    def test_collapse_across_all_three_rfc1918(self):
        ips = (
            [f"10.{i}.0.1" for i in range(0, 10)]
            + [f"172.16.{i}.1" for i in range(0, 10)]
            + [f"192.168.{i}.1" for i in range(0, 10)]
        )
        result = collapse_ips_to_cidrs(ips, max_rules=6)
        self.assertLessEqual(len(result), 6)
        nets = [ipaddress.ip_network(c) for c in result]
        for ip in ips:
            self.assertTrue(any(ipaddress.ip_address(ip) in n for n in nets))

    def test_force_fit_never_crosses_rfc1918_boundary(self):
        # Three RFC 1918 ranges, ask for 3 rules — one per range. Force-fit
        # must not promote two ranges into a single covering net that
        # straddles the boundary.
        ips = ["10.0.0.1", "172.16.0.1", "192.168.0.1"]
        result = collapse_ips_to_cidrs(ips, max_rules=3, tolerance=0.99)
        nets = [ipaddress.ip_network(c) for c in result]
        for n in nets:
            self.assertTrue(
                any(n.subnet_of(b) for b in (
                    ipaddress.ip_network("10.0.0.0/8"),
                    ipaddress.ip_network("172.16.0.0/12"),
                    ipaddress.ip_network("192.168.0.0/16"),
                )),
                f"net {n} escaped RFC 1918",
            )

    def test_ignores_invalid_inputs(self):
        ips = ["10.0.0.1", "not-an-ip", "", None, "999.999.999.999"]
        # We pass only valid IPs in; the rest should be silently filtered.
        result = collapse_ips_to_cidrs([i for i in ips if i is not None])
        nets = [ipaddress.ip_network(c) for c in result]
        self.assertTrue(any(ipaddress.ip_address("10.0.0.1") in n for n in nets))

    def test_tolerance_zero_keeps_blocks_tight(self):
        # With zero tolerance every observed IP becomes a /32.
        ips = ["10.0.0.1", "10.0.0.3", "10.0.0.5"]
        result = collapse_ips_to_cidrs(ips, max_rules=10, tolerance=0.0)
        for c in result:
            self.assertEqual(ipaddress.ip_network(c).prefixlen, 32)


class TestRuleEligibility(unittest.TestCase):
    def test_public_any_not_eligible(self):
        self.assertFalse(rule_is_eligible("0.0.0.0/0"))

    def test_overlapping_non_private_not_eligible(self):
        # 192.0.0.0/4 overlaps 192.168.0.0/16 but is not a strict subset.
        self.assertFalse(rule_is_eligible("192.0.0.0/4"))

    def test_strict_rfc1918_subset_eligible(self):
        self.assertTrue(rule_is_eligible("10.0.0.0/16"))
        self.assertTrue(rule_is_eligible("172.16.0.0/12"))
        self.assertTrue(rule_is_eligible("192.168.0.0/16"))

    def test_already_tight_not_eligible(self):
        self.assertFalse(rule_is_eligible("10.0.0.0/24"))
        self.assertFalse(rule_is_eligible("10.0.0.0/25"))

    def test_prefix_threshold_configurable(self):
        # Default threshold is 24, but caller can tighten.
        self.assertTrue(rule_is_eligible("10.0.0.0/20", prefix_threshold=24))
        self.assertFalse(rule_is_eligible("10.0.0.0/22", prefix_threshold=20))

    def test_invalid_cidr(self):
        self.assertFalse(rule_is_eligible(None))
        self.assertFalse(rule_is_eligible(""))
        self.assertFalse(rule_is_eligible("garbage"))


class TestPortRangeMerging(unittest.TestCase):
    def test_adjacent_ranges_merge(self):
        self.assertEqual(merge_port_ranges([(80, 89), (90, 99)]), [(80, 99)])

    def test_overlapping_ranges_merge(self):
        self.assertEqual(merge_port_ranges([(80, 100), (90, 120)]), [(80, 120)])

    def test_disjoint_ranges_stay(self):
        self.assertEqual(merge_port_ranges([(80, 89), (200, 220)]), [(80, 89), (200, 220)])

    def test_empty(self):
        self.assertEqual(merge_port_ranges([]), [])

    def test_reversed_pair_normalised(self):
        self.assertEqual(merge_port_ranges([(99, 80)]), [(80, 99)])


class TestParsePartitionFromArn(unittest.TestCase):
    """OU report partition detection must handle all AWS partitions."""

    def test_aws_partition(self):
        self.assertEqual(parse_partition_from_arn("arn:aws:iam::123:user/joe"), "aws")

    def test_aws_cn_partition(self):
        self.assertEqual(parse_partition_from_arn("arn:aws-cn:iam::123:user/joe"), "aws-cn")

    def test_aws_us_gov_partition(self):
        self.assertEqual(
            parse_partition_from_arn("arn:aws-us-gov:iam::123:user/joe"),
            "aws-us-gov",
        )

    def test_unknown_partition_defaults_to_aws(self):
        self.assertEqual(parse_partition_from_arn("arn:aws-future:iam::123:user/joe"), "aws")

    def test_garbage_defaults_to_aws(self):
        self.assertEqual(parse_partition_from_arn(""), "aws")
        self.assertEqual(parse_partition_from_arn(None), "aws")
        self.assertEqual(parse_partition_from_arn("not-an-arn"), "aws")


class TestComputeRiskScore(unittest.TestCase):
    """Account ranking must give CRITICAL findings overwhelmingly more weight."""

    def test_single_critical_outranks_many_lows(self):
        critical_only = compute_risk_score(1, 0, 0, 0)
        many_lows = compute_risk_score(0, 0, 0, 100)
        self.assertGreater(critical_only, many_lows)

    def test_high_outranks_many_meds(self):
        self.assertGreater(
            compute_risk_score(0, 1, 0, 0),
            compute_risk_score(0, 0, 50, 0),
        )

    def test_zero_findings(self):
        self.assertEqual(compute_risk_score(0, 0, 0, 0), 0)

    def test_severity_order(self):
        c = compute_risk_score(1, 0, 0, 0)
        h = compute_risk_score(0, 1, 0, 0)
        m = compute_risk_score(0, 0, 1, 0)
        l = compute_risk_score(0, 0, 0, 1)
        self.assertGreater(c, h)
        self.assertGreater(h, m)
        self.assertGreater(m, l)


class TestClassifySgRule(unittest.TestCase):
    def test_public_ssh_is_critical(self):
        self.assertEqual(classify_sg_rule("0.0.0.0/0", 22, 22), "CRITICAL")

    def test_public_https_is_high(self):
        self.assertEqual(classify_sg_rule("0.0.0.0/0", 443, 443), "HIGH")

    def test_slash_16_private_is_high(self):
        self.assertEqual(classify_sg_rule("10.0.0.0/16", 443, 443), "HIGH")

    def test_slash_24_private_is_not_classified(self):
        self.assertIsNone(classify_sg_rule("10.0.0.0/24", 443, 443))

    def test_invalid_cidr_returns_none(self):
        self.assertIsNone(classify_sg_rule("garbage", 22, 22))


class TestSgExtendInputValidation(unittest.TestCase):
    def test_cidr_must_include_prefix(self):
        self.assertEqual(parse_cidr("10.0.0.0/24"), "10.0.0.0/24")
        with self.assertRaises(ValueError):
            parse_cidr("10.0.0.0")

    def test_cidr_rejects_garbage(self):
        with self.assertRaises(ValueError):
            parse_cidr("not-a-cidr/24")

    def test_port_single(self):
        self.assertEqual(parse_port_spec("443"), (443, 443))

    def test_port_range(self):
        self.assertEqual(parse_port_spec("8000-8100"), (8000, 8100))

    def test_port_out_of_range(self):
        with self.assertRaises(ValueError):
            parse_port_spec("70000")

    def test_port_reversed(self):
        with self.assertRaises(ValueError):
            parse_port_spec("100-50")

    def test_port_garbage(self):
        with self.assertRaises(ValueError):
            parse_port_spec("abc")
        with self.assertRaises(ValueError):
            parse_port_spec("")

    def test_group_id_format(self):
        self.assertEqual(parse_group_id("sg-0123456789abcdef0"), "sg-0123456789abcdef0")
        self.assertEqual(parse_group_id("sg-12345678"), "sg-12345678")

    def test_group_id_rejects_garbage(self):
        with self.assertRaises(ValueError):
            parse_group_id("not-a-group")
        with self.assertRaises(ValueError):
            parse_group_id("sg-XYZ")


class TestSgExtendDiscovery(unittest.TestCase):
    """Flow-log-driven break-glass logic — all pure, no AWS required."""

    def test_proto_name_known(self):
        self.assertEqual(proto_name("6"), "tcp")
        self.assertEqual(proto_name("17"), "udp")

    def test_proto_name_unknown_or_garbage(self):
        self.assertIsNone(proto_name("1"))    # icmp — no port-scoped rule
        self.assertIsNone(proto_name("47"))   # gre
        self.assertIsNone(proto_name(""))
        self.assertIsNone(proto_name(None))

    def test_filter_keeps_private_drops_public(self):
        flows = {
            ("10.0.0.5", "tcp", 443),
            ("192.168.1.7", "tcp", 5432),
            ("8.8.8.8", "tcp", 443),       # public — dropped by default
        }
        out = filter_flows(flows, include_public=False, port_specs=None)
        self.assertIn(("10.0.0.5", "tcp", 443), out)
        self.assertIn(("192.168.1.7", "tcp", 5432), out)
        self.assertNotIn(("8.8.8.8", "tcp", 443), out)

    def test_filter_include_public(self):
        flows = {("8.8.8.8", "tcp", 443)}
        self.assertEqual(
            filter_flows(flows, include_public=True, port_specs=None),
            {("8.8.8.8", "tcp", 443)},
        )

    def test_filter_drops_ipv6_and_garbage(self):
        flows = {("::1", "tcp", 443), ("not-an-ip", "tcp", 443)}
        self.assertEqual(filter_flows(flows, include_public=True, port_specs=None), set())

    def test_filter_port_specs(self):
        flows = {
            ("10.0.0.1", "tcp", 443),
            ("10.0.0.2", "tcp", 22),
            ("10.0.0.3", "tcp", 8050),
        }
        out = filter_flows(flows, include_public=False, port_specs=[(443, 443), (8000, 8100)])
        self.assertEqual(
            out, {("10.0.0.1", "tcp", 443), ("10.0.0.3", "tcp", 8050)}
        )

    def test_build_perms_groups_by_proto_port(self):
        flows = {
            ("10.0.0.1", "tcp", 443),
            ("10.0.0.2", "tcp", 443),
            ("10.0.0.1", "tcp", 5432),
        }
        perms = build_perms(flows, "test", tolerance=0.0, max_rules=60)
        # One permission per (proto, port).
        self.assertEqual(len({(p["FromPort"], p["ToPort"]) for p in perms}), 2)
        # Every discovered flow is covered by the resulting CIDRs.
        for src, _proto, port in flows:
            perm = next(p for p in perms if p["FromPort"] == port)
            nets = [ipaddress.ip_network(ip["CidrIp"]) for ip in perm["IpRanges"]]
            self.assertTrue(any(ipaddress.ip_address(src) in n for n in nets))

    def test_build_perms_tolerance_zero_keeps_host_routes(self):
        flows = {("10.0.0.1", "tcp", 443), ("10.0.5.9", "tcp", 443)}
        perms = build_perms(flows, "t", tolerance=0.0, max_rules=60)
        cidrs = {ip["CidrIp"] for p in perms for ip in p["IpRanges"]}
        self.assertEqual(cidrs, {"10.0.0.1/32", "10.0.5.9/32"})

    def test_build_perms_tolerance_collapses_dense_block(self):
        # A dense /24 worth of sources should collapse to far fewer rules
        # once we tolerate unused addresses.
        flows = {(f"10.0.0.{i}", "tcp", 443) for i in range(1, 60)}
        perms = build_perms(flows, "t", tolerance=0.5, max_rules=60)
        self.assertLess(perm_rule_count(perms), len(flows))
        nets = [ipaddress.ip_network(ip["CidrIp"]) for p in perms for ip in p["IpRanges"]]
        for src, _proto, _port in flows:
            self.assertTrue(any(ipaddress.ip_address(src) in n for n in nets))

    def test_rule_count_counts_all_rule_kinds(self):
        sg = {"IpPermissions": [{
            "IpProtocol": "tcp", "FromPort": 443, "ToPort": 443,
            "IpRanges": [{"CidrIp": "10.0.0.0/16"}, {"CidrIp": "10.1.0.0/16"}],
            "Ipv6Ranges": [{"CidrIpv6": "::/0"}],
            "UserIdGroupPairs": [{"GroupId": "sg-1"}],
        }]}
        self.assertEqual(_rule_count(sg), 4)

    def test_existing_nets_for_matches_proto_port_and_all(self):
        sg = {"IpPermissions": [
            {"IpProtocol": "tcp", "FromPort": 443, "ToPort": 443,
             "IpRanges": [{"CidrIp": "10.0.0.0/16"}]},
            {"IpProtocol": "-1", "FromPort": None, "ToPort": None,
             "IpRanges": [{"CidrIp": "192.168.0.0/16"}]},
            {"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22,
             "IpRanges": [{"CidrIp": "172.16.0.0/12"}]},
        ]}
        nets = _existing_nets_for(sg, "tcp", 443)
        strs = {str(n) for n in nets}
        self.assertIn("10.0.0.0/16", strs)     # exact proto/port
        self.assertIn("192.168.0.0/16", strs)  # protocol -1 covers all ports
        self.assertNotIn("172.16.0.0/12", strs)  # different port

    def test_filter_existing_drops_covered_candidates(self):
        sg = {"IpPermissions": [{
            "IpProtocol": "tcp", "FromPort": 443, "ToPort": 443,
            "IpRanges": [{"CidrIp": "10.0.0.0/16"}],
        }]}
        perms = [{
            "IpProtocol": "tcp", "FromPort": 443, "ToPort": 443,
            "IpRanges": [
                {"CidrIp": "10.0.5.0/24"},   # covered by 10.0.0.0/16 -> dropped
                {"CidrIp": "10.9.0.0/24"},   # not covered -> kept
            ],
        }]
        out = filter_existing(perms, sg)
        kept = {ip["CidrIp"] for p in out for ip in p["IpRanges"]}
        self.assertEqual(kept, {"10.9.0.0/24"})


class TestStrictRfc1918(unittest.TestCase):
    def test_strict_rfc1918_helpers(self):
        self.assertTrue(_is_strict_rfc1918(ipaddress.ip_network("10.0.0.0/16")))
        self.assertTrue(_is_strict_rfc1918(ipaddress.ip_network("172.20.0.0/16")))
        self.assertFalse(_is_strict_rfc1918(ipaddress.ip_network("172.40.0.0/16")))
        self.assertFalse(_is_strict_rfc1918(ipaddress.ip_network("192.0.0.0/4")))
        self.assertFalse(_is_strict_rfc1918(ipaddress.ip_network("0.0.0.0/0")))


if __name__ == "__main__":
    runner = unittest.TextTestRunner(verbosity=2)
    suite = unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
