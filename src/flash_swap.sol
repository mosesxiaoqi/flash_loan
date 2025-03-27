// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IUniswapV2Callee} from "@uniswapv2-solc0.8/contracts/interfaces/IUniswapV2Callee.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV2Pair} from "@uniswapv2-solc0.8/contracts/interfaces/IUniswapV2Pair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/UniswapV2Library.sol";

contract FlashSwap {
    address public owner;
    // uniswap v2 factory address
    address immutable factory1;
    address immutable factory2;

    //部署两个dex的工厂合约
    constructor(
        address _factory1,
        address _factory2
    ) public Ownable(msg.sender) {
        factory1 = _factory;
        factory2 = _factory2;
    }

    receive() external payable {}

    // 传入两个代币地址，两个代币的数量，以及最小的输出数量
    // 由于通过工厂合约获取交易对合约地址
    // 所以不用判断两个token地址的大小
    function startFlashSwap(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 amountOutMin
    ) external onlyOwner {
        // 判断tokenA和tokenB是不能相同
        require(tokenA == tokenB, "tokenA == tokenB");
        // amountA和amountB至少有一个是不能为0
        require(amountA > 0 && amountB > 0, "amountA > 0 && amountB > 0");

        // 通过工厂合约和token地址获取交易对合约地址
        address pair1 = UniswapV2Library.pairFor(factory1, tokenA, tokenB);
        address pair2 = UniswapV2Library.pairFor(factory2, tokenA, tokenB);

        // 由于token的地址在创建交易对时已经排序，所以不用在读取交易对里的token0和token1
        // 直接判断两个token的大小来决定uint256 amount0, uint256 amount1
        (uint256 amount0, uint256 amount1) = tokenA < tokenB
            ? (amountA, amountB)
            : (amountB, amountA);

        // 传递滑点参数
        bytes memory hookCallData = abi.encode(amountOutMin);

        IUniswapV2Pair(pair1).swap(
            amount0,
            amount1,
            address(this),
            hookCallData
        );
    }

    function uniswapV2Call(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external {
        // do something
    }

    function withdraw() external {
        // do something
    }
}
