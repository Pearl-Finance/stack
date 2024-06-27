// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {console2 as console} from "forge-std/Test.sol";

struct AddressSet {
    address[] addrs;
    address[] leverageAddrs;
    mapping(address => bool) saved;
    mapping(address => bool) leverageSaved;
}

library LibAddressSet {
    function add(AddressSet storage s, address addr) internal {
        if (!s.saved[addr]) {
            s.addrs.push(addr);
            s.saved[addr] = true;
        }
    }

    function addForLeverage(AddressSet storage s, address addr) internal {
        if (!s.leverageSaved[addr]) {
            s.leverageAddrs.push(addr);
            s.leverageSaved[addr] = true;
        }
    }

    function rand(AddressSet storage s, uint256 seed) internal view returns (address) {
        if (s.addrs.length > 0) {
            return s.addrs[seed % s.addrs.length];
        } else {
            return address(0);
        }
    }

    function randForLeverage(AddressSet storage s, uint256 seed) internal view returns (address) {
        if (s.leverageAddrs.length > 0) {
            return s.leverageAddrs[seed % s.leverageAddrs.length];
        } else {
            return address(0);
        }
    }

    function reduce(AddressSet storage s, uint256 acc, function(uint256, address) external returns (uint256) func)
        internal
        returns (uint256)
    {
        for (uint256 i; i < s.addrs.length; ++i) {
            acc = func(acc, s.addrs[i]);
        }
        return acc;
    }

    function forEach(AddressSet storage s, function(address) external func) internal {
        for (uint256 i; i < s.addrs.length; ++i) {
            func(s.addrs[i]);
        }
    }

    function testExcluded() public {}
}
