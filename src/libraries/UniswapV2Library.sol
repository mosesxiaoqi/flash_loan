pragma solidity >=0.5.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "./SafeMath.sol";

library UniswapV2Library {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        // 判断两个token地址是否相同
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        // 比较两个token地址的大小，小的地址作为token0，大的地址作为token1
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        // 判断token0是否为0地址
        // token0小于token1，如果token0不为0地址，则两个token地址都不为0地址
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(
        address factory,
        address tokenA,
        address tokenB
    ) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        factory,
                        keccak256(abi.encodePacked(token0, token1)),
                        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                    )
                )
            )
        );
    }

    // fetches and sorts the reserves for a pair
    // 获取 Uniswap V2 交易对中两个代币的当前储备量（reserves）
    function getReserves(
        address factory, // Uniswap V2 工厂合约的地址
        address tokenA,
        address tokenB
    ) internal view returns (uint reserveA, uint reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        // 使用 `pairFor` 函数计算代币对的交易对合约地址
        // 调用交易对的 `getReserves()` 函数获取当前储备量
        (uint reserve0, uint reserve1, ) = IUniswapV2Pair(
            pairFor(factory, tokenA, tokenB)
        ).getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(
        uint amountA,
        uint reserveA,
        uint reserveB
    ) internal pure returns (uint amountB) {
        require(amountA > 0, "UniswapV2Library: INSUFFICIENT_AMOUNT");
        require(
            reserveA > 0 && reserveB > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // `amountIn`: 输入的代币数量
    // `reserveIn`: 交易对中输入代币的储备量
    // `reserveOut`: 交易对中输出代币的储备量
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) internal pure returns (uint amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        // 理论公式： (reserveIn + amountIn * 0.997) * (reserveOut - amountOut) = reserveIn * reserveOut
        // 推导过程： (reserveOut - amountOut) = (reserveIn * reserveOut) / (reserveIn + amountIn * 0.997)
        // 推导过程： amountOut = reserveOut - (reserveIn * reserveOut) / (reserveIn + amountIn * 0.997)
        // 推导过程： amountOut = (reserveOut*(reserveIn + amountIn * 0.997))/(reserveIn + amountIn * 0.997) - (reserveIn * reserveOut) / (reserveIn + amountIn * 0.997)
        // 推导过程： amountOut = (reserveOut*(reserveIn + amountIn * 0.997) - (reserveIn * reserveOut)) / (reserveIn + amountIn * 0.997)
        // 推导过程： amountOut = (reserveOut*reserveIn + reserveOut*amountIn*0.997 - reserveIn * reserveOut) / (reserveIn + amountIn * 0.997)
        // 推导过程： amountOut = (reserveOut*amountIn*0.997) / (reserveIn + amountIn * 0.997)
        // 推导过程： amountOut = (reserveOut*amountIn*997) / (reserveIn*1000 + amountIn * 997)
        // 推导过程： 乘1000是为了减少精度损失，因为amountIn是用户输入的，所以可能是小数
        // 推导过程： 所以分子就是reserveOut.mul(amountIn).mul(997)
        // 推导过程： 所以分母就是reserveIn.mul(1000).add(amountIn.mul(997))
        /**
            1. **避免浮点数运算**：
            - 以太坊智能合约不支持浮点数运算
            - 直接使用 0.997 这样的小数是不可能的

            2. **分数表示**：
            - 手续费率 0.3% 等同于 3/1000
            - 保留率（扣除手续费后的比例）为 (1000-3)/1000 = 997/1000

            3. **整数运算中保持精度**：
            - 乘以 1000 然后用 997 进行相应计算，可以在整数环境中精确表达这个比例
            - 这种分子/分母的处理方式避免了浮点数计算的需求
        */
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // `amountOut`: 希望获得的输出代币数量
    // `reserveIn`: 交易对中输入代币的储备量
    // `reserveOut`: 交易对中输出代币的储备量
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) internal pure returns (uint amountIn) {
        // 希望获得的输出代币数量必须大于0
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        // 交易对中输入代币的储备量和输出代币的储备量都必须大于0
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        // 由于交易存在千三手续费，
        // 而手续费是随着交易一块进入了交易对的储备量
        // 所以在计算时要去掉这部分手续费
        // 千三就是0.003，所以总量的0.997就是去掉千三手续费后我们需要的数量
        // 注意⚠️：只有存入有手续费，提取没有
        // 理论公式：(reserveIn + amountIn * 0.997) * (reserveOut - amountOut) = reserveIn * reserveOut
        // 推导过程： reserveIn + amountIn * 0.997 = (reserveIn * reserveOut) / (reserveOut - amountOut)
        // 推导过程： amountIn * 0.997 = (reserveIn * reserveOut) / (reserveOut - amountOut) - reserveIn
        // 推导过程： reserveIn = reserveIn*1，所以将reserveIn*{(reserveOut - amountOut)/(reserveOut - amountOut)}，同时扩大分子分母
        // 推导过程： amountIn * 0.997 = (reserveIn * reserveOut - reserveIn*(reserveOut - amountOut)) / (reserveOut - amountOut)
        // 推导过程： 接下来提取reserveIn
        // 推导过程： amountIn * 0.997 = (reserveIn*(reserveOut - (reserveOut - amountOut))) / (reserveOut - amountOut)
        // 推导过程： amountIn * 0.997 = (reserveIn*amountOut) / (reserveOut - amountOut)
        // 推导过程： 同时将两边*1000
        // 推导过程： amountIn * 997 = (reserveIn*amountOut*1000) / (reserveOut - amountOut)
        // 推导过程： 除以997，就是*997分之1，就得到了amountIn
        // 推导过程： amountIn = (reserveIn*amountOut*1000) / （(reserveOut - amountOut) * 997）
        // 推导过程： 所以分母就是reserveIn*amountOut*1000，代码就是reserveIn.mul(amountOut).mul(1000)
        // 推导过程： 所以分子就是(reserveOut - amountOut) * 997，代码就是reserveOut.sub(amountOut).mul(997)
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        // 1. Solidity中的整数除法会自动截断小数部分（向下取整）
        // 2. 然后代码添加1，有效地将结果向上取整
        // 向下取整会导致amountIn变小，期望获得的输出代币数量不足，所以需要向上取整
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(
        address factory,
        uint amountIn,
        address[] memory path
    ) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(
                factory,
                path[i],
                path[i + 1]
            );
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(
        address factory,
        uint amountOut,
        address[] memory path
    ) internal view returns (uint[] memory amounts) {
        // path数组是交易路径，表达path[0] → path[1] → ... → path[path.length - 1]
        // path数组的长度至少为2
        require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
        // 创建一个长度为path.length的数组
        amounts = new uint[](path.length);
        // 最后一个元素的值为amountOut
        // 表示交易路径中最后一个代币是要借入的代币，amountOut是借入的数量
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            // 获取交易对中两个代币的当前储备量
            (uint reserveIn, uint reserveOut) = getReserves(
                factory,
                path[i - 1],
                path[i]
            );
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
