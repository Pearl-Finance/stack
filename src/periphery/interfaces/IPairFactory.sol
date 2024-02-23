pragma solidity =0.8.20;

interface IPairFactory {
    function allPairsLength() external view returns (uint256);
    function allPairs(uint256) external view returns (address);
}
