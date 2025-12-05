// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {ISwapRouter} from "../../src/inerfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock UniswapV3 Router
contract MockUniswapV3Router is ISwapRouter {
    mapping(address => mapping(address => uint256)) public swapRates; // tokenIn => tokenOut => rate (multiplied by 1e18)

    function setSwapRate(address tokenIn, address tokenOut, uint256 rate) external {
        swapRates[tokenIn][tokenOut] = rate;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        uint256 rate = swapRates[params.tokenIn][params.tokenOut];
        if (rate == 0) {
            rate = 1e18; // Default 1:1 if not set
        }
        amountOut = (params.amountIn * rate) / 1e18;
        require(amountOut >= params.amountOutMinimum, "Insufficient output amount");

        // Transfer tokens
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        IERC20(params.tokenOut).transfer(params.recipient, amountOut);

        return amountOut;
    }

    function exactInput(ExactInputParams calldata params) external payable override returns (uint256 amountOut) {
        // Decode path: token0 (20 bytes) + fee (3 bytes) + token1 (20 bytes)
        require(params.path.length >= 43, "Invalid path");
        address tokenIn = address(bytes20(params.path[0:20]));
        address tokenOut = address(bytes20(params.path[23:43]));

        uint256 rate = swapRates[tokenIn][tokenOut];
        if (rate == 0) {
            rate = 1e18; // Default 1:1 if not set
        }
        amountOut = (params.amountIn * rate) / 1e18;
        require(amountOut >= params.amountOutMinimum, "Insufficient output amount");

        // Transfer tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        IERC20(tokenOut).transfer(params.recipient, amountOut);

        return amountOut;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        uint256 rate = swapRates[params.tokenIn][params.tokenOut];
        if (rate == 0) {
            rate = 1e18; // Default 1:1 if not set
        }
        // Reverse calculation: amountIn = amountOut * 1e18 / rate
        amountIn = (params.amountOut * 1e18) / rate;
        require(amountIn <= params.amountInMaximum, "Excessive input amount");

        // Transfer tokens
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(params.tokenOut).transfer(params.recipient, params.amountOut);

        return amountIn;
    }

    function exactOutput(ExactOutputParams calldata params) external payable override returns (uint256 amountIn) {
        // Decode path: token0 (20 bytes) + fee (3 bytes) + token1 (20 bytes)
        require(params.path.length >= 43, "Invalid path");
        address tokenIn = address(bytes20(params.path[0:20]));
        address tokenOut = address(bytes20(params.path[23:43]));

        uint256 rate = swapRates[tokenIn][tokenOut];
        if (rate == 0) {
            rate = 1e18; // Default 1:1 if not set
        }
        // Reverse calculation: amountIn = amountOut * 1e18 / rate
        amountIn = (params.amountOut * 1e18) / rate;
        require(amountIn <= params.amountInMaximum, "Excessive input amount");

        // Transfer tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(params.recipient, params.amountOut);

        return amountIn;
    }

    // Callback implementation (not used in mocks, but required by interface)
    function uniswapV3SwapCallback(int256, int256, bytes calldata) external pure override {
        revert("Not implemented");
    }
}

