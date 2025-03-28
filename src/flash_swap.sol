// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IUniswapV2Callee} from "@uniswapv2-solc0.8/contracts/interfaces/IUniswapV2Callee.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV2Pair} from "@uniswapv2-solc0.8/contracts/interfaces/IUniswapV2Pair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/UniswapV2Library.sol";

contract FlashSwap is IUniswapV2Callee, Ownable {
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
        /*
            1. **动态分配**：
            - token0 和 token1 的角色不是由用户调用 `createPair(tokenA, tokenB)` 时参数的顺序决定的
            - 而是由代币合约地址的大小比较后自动确定的

            2. **字典序比较**：
            - 系统会比较两个代币地址的十六进制值
            - 地址值较小的代币被指定为 token0
            - 地址值较大的代币被指定为 token1
        */
        (uint256 amount0, uint256 amount1) = tokenA < tokenB
            ? (amountA, amountB)
            : (amountB, amountA);

        // 传递滑点参数
        bytes memory hookCallData = abi.encode(pair2);

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
        /*
            amount0和amount1代表的是token0和token1的数量
            我们的业务是从pair1中取出tokenA，然后将tokenA转移到pair2中
            所以amount0和amount1其中不是0的一个就是tokenA的数量
            所以我们需要通过判断amount0和amount1哪一个不是0来确定tokenA和tokenB的地址
            计算出要还的tokenB的数量和计算出兑换pair2池子中tokenB的数量
            判断是否有利润
            uniswap采用乐观模式，所以是先转移tokenA给pair2，然后再swap tokenB
            将tokenB还给pair1
            将利润转移给owner
        */
        require(amount0 > 0 || amount1 > 0, 'amount not 0!' )
        address pair1 = msg.sender;
        address pair2 = abi.decode(data, (address));
        // 都是uniswap v2 的交易对合约地址
        // 所以获取的token0和token1的地址顺序是一样的
        address token0 = IUniswapV2Pair(pair1).token0();
        address token1 = IUniswapV2Pair(pair1).token1();

        // (address tokenA, address tokenB) = token0 < token1 ? (token0, token1) : (token1, token0);
        (uint amountA, uint amountB )= amount0 != 0 ? (amount0, amount1) : (amount1, amount0);
        (address tokenA, address tokenB) = amount0 != 0 ? (token0, token1) : (token1, token0);

        // 这里获取的池子总量是以及发生了tokenA的转移后，那获取的是转移后的池子总量，这不是有问题吗？
        // 其实这里获取的不是转移后的池子总量，而是代表交易对上次更新时记录的代币数量
        // 只在交易结束时更新，看v2的swap函数会发现，总量就是在交易结束时将代币的余额更新
        // 所以这里获取的不是实际池子的数量
        (uint reserve0, uint reserve1, ) = IUniswapV2Pair(pair1).getReserves();
        (uint reserveIn, uint reserveOut) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        uint amountRequired = UniswapV2Library.getAmountIn(amountA, reserveIn, reserveOut);

        IERC20(tokenA).transfer(pair2, amountA);
        (uint reserve0, uint reserve1, ) = IUniswapV2Pair(pair2).getReserves();
        (uint reserveIn, uint reserveOut) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        uint amountReceived = UniswapV2Library.getAmountOut(amountA, reserveIn, reserveOut);
        require(amountReceived > amountRequired, 'amountReceived < amountRequired');
        IUniswapV2Pair(pair2).swap(amountA, amountB, address(this), new bytes(0));

        IERC20(tokenB).transfer(pair1, amountRequired);

        // 将利润（剩余的 tokenB）转移给调用者
        uint profit = IERC20(tokenB).balanceOf(address(this));
        IERC20(tokenB).transfer(owner, profit);


    }

    function withdraw() external {
        // do something
    }
}
