// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@layerzerolabs/contracts/lzApp/mocks/LZEndpointMock.sol";

import "@openzeppelin/contracts/interfaces/IERC3156.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import "src/tokens/More.sol";
import "src/tokens/MoreMinter.sol";

contract MoreTest is Test, IERC3156FlashBorrower {
    More more;

    function setUp() public {
        LZEndpointMock lzEndpoint = new LZEndpointMock(uint16(block.chainid));
        More impl = new More(address(lzEndpoint));
        bytes memory init = abi.encodeCall(impl.initialize, (address(1)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), init);
        more = More(address(proxy));
        MoreMinter minter = new MoreMinter(address(proxy));
        init = abi.encodeCall(minter.initialize, (address(this), address(1)));
        ERC1967Proxy minterProxy = new ERC1967Proxy(address(minter), init);
        minter = MoreMinter(address(minterProxy));
        more.setMinter(address(minter));
        minter.mint(address(this), 1_000_000 ether);
    }

    function testMetadata() public {
        assertEq(more.symbol(), "MORE");
        assertEq(more.name(), "MORE");
        assertEq(more.decimals(), 18);
        assertEq(more.owner(), address(this));
    }

    function testInitialState() public {
        assertEq(more.balanceOf(address(this)), 1_000_000 ether);
        assertEq(more.maxFlashLoan(address(more)), type(uint256).max - 1_000_000 ether);
        assertEq(more.maxFlashLoan(address(1234)), 0);
        assertEq(more.flashFee(address(more), 1234), 0);
    }

    function testFlashMint() public {
        more.flashLoan(this, address(more), 1_000 ether, abi.encode(1_000 ether));
        more.flashLoan(this, address(more), 1_000 ether, abi.encode(1_100 ether));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(more), 0, 1_000 ether)
        );
        more.flashLoan(this, address(more), 1_000 ether, abi.encode(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(more), 500 ether, 1_000 ether
            )
        );
        more.flashLoan(this, address(more), 1_000 ether, abi.encode(500 ether));

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20FlashMintUpgradeable.ERC3156ExceededMaxLoan.selector, type(uint256).max - more.totalSupply()
            )
        );
        more.flashLoan(this, address(more), type(uint256).max, abi.encode(type(uint256).max));

        vm.expectRevert(abi.encodeWithSelector(ERC20FlashMintUpgradeable.ERC3156ExceededMaxLoan.selector, 0));
        more.flashLoan(this, address(1), 1, abi.encode(1));
    }

    function onFlashLoan(address initiator, address token, uint256, uint256 fee, bytes calldata data)
        external
        returns (bytes32)
    {
        uint256 repayAmount = abi.decode(data, (uint256));
        assertEq(initiator, address(this));
        assertEq(token, address(more));
        assertEq(fee, 0);
        More(more).approve(address(more), repayAmount);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
