// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Custom errors
error InvalidPath();

// Mock UniswapV2 Router
contract MockUniswapV2Router is IUniswapV2Router02 {
    mapping(address => mapping(address => uint256)) public swapRates; // tokenIn => tokenOut => rate (multiplied by 1e18)

    function setSwapRate(address tokenIn, address tokenOut, uint256 rate) external {
        swapRates[tokenIn][tokenOut] = rate;
    }

    function swapExactTokensForTokens(uint256 amountIn, uint256, address[] calldata path, address to, uint256)
        external
        override
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, InvalidPath());
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        uint256 rate = swapRates[tokenIn][tokenOut];
        if (rate == 0) {
            rate = 1e18; // Default 1:1 if not set
        }
        uint256 amountOut = (amountIn * rate) / 1e18;

        // Transfer tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(to, amountOut);

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOut;
        return amounts;
    }

    // Stub implementations for interface compliance
    function factory() external pure override returns (address) {
        return address(0);
    }

    function WETH() external pure override returns (address) {
        return address(0);
    }

    function addLiquidity(address, address, uint256, uint256, uint256, uint256, address, uint256)
        external
        pure
        override
        returns (uint256, uint256, uint256)
    {
        revert("Not implemented");
    }

    function addLiquidityETH(address, uint256, uint256, uint256, address, uint256)
        external
        payable
        override
        returns (uint256, uint256, uint256)
    {
        revert("Not implemented");
    }

    function removeLiquidity(address, address, uint256, uint256, uint256, address, uint256)
        external
        pure
        override
        returns (uint256, uint256)
    {
        revert("Not implemented");
    }

    function removeLiquidityETH(address, uint256, uint256, uint256, address, uint256)
        external
        pure
        override
        returns (uint256, uint256)
    {
        revert("Not implemented");
    }

    function removeLiquidityWithPermit(
        address,
        address,
        uint256,
        uint256,
        uint256,
        address,
        uint256,
        bool,
        uint8,
        bytes32,
        bytes32
    ) external pure override returns (uint256, uint256) {
        revert("Not implemented");
    }

    function removeLiquidityETHWithPermit(
        address,
        uint256,
        uint256,
        uint256,
        address,
        uint256,
        bool,
        uint8,
        bytes32,
        bytes32
    ) external pure override returns (uint256, uint256) {
        revert("Not implemented");
    }

    function swapTokensForExactTokens(uint256, uint256, address[] calldata, address, uint256)
        external
        pure
        override
        returns (uint256[] memory)
    {
        revert("Not implemented");
    }

    function swapExactETHForTokens(uint256, address[] calldata, address, uint256)
        external
        payable
        override
        returns (uint256[] memory)
    {
        revert("Not implemented");
    }

    function swapTokensForExactETH(uint256, uint256, address[] calldata, address, uint256)
        external
        pure
        override
        returns (uint256[] memory)
    {
        revert("Not implemented");
    }

    function swapExactTokensForETH(uint256, uint256, address[] calldata, address, uint256)
        external
        pure
        override
        returns (uint256[] memory)
    {
        revert("Not implemented");
    }

    function swapETHForExactTokens(uint256, address[] calldata, address, uint256)
        external
        payable
        override
        returns (uint256[] memory)
    {
        revert("Not implemented");
    }

    function quote(uint256, uint256, uint256) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function getAmountOut(uint256, uint256, uint256) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function getAmountIn(uint256, uint256, uint256) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function getAmountsOut(uint256, address[] calldata) external pure override returns (uint256[] memory) {
        revert("Not implemented");
    }

    function getAmountsIn(uint256, address[] calldata) external pure override returns (uint256[] memory) {
        revert("Not implemented");
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(address, uint256, uint256, uint256, address, uint256)
        external
        pure
        override
        returns (uint256)
    {
        revert("Not implemented");
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address,
        uint256,
        uint256,
        uint256,
        address,
        uint256,
        bool,
        uint8,
        bytes32,
        bytes32
    ) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external pure override {
        revert("Not implemented");
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(uint256, address[] calldata, address, uint256)
        external
        payable
        override
    {
        revert("Not implemented");
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256, uint256, address[] calldata, address, uint256)
        external
        pure
        override
    {
        revert("Not implemented");
    }
}

