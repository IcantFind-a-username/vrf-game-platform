# SC6107 3号交付物：Lottery + Referral

## 文件清单

```
3-交付物/
├── contracts/src/
│   ├── Lottery.sol              # 彩票/抽奖主合约
│   ├── Referral.sol             # 推荐返佣合约 (Bonus)
│   └── interfaces/
│       ├── IVRFConsumer.sol     # VRF 随机数接口（对接1号）
│       ├── ITreasury.sol        # Treasury 金库接口（对接1号）
│       └── IRandomnessConsumer.sol  # VRF 回调接口（对接1号）
├── test/
│   ├── Lottery.t.sol            # Lottery 单元测试 (49 tests)
│   ├── Referral.t.sol           # Referral 单元测试 (20 tests)
│   └── mocks/
│       ├── MockVRFConsumer.sol  # Mock VRF
│       ├── MockTreasury.sol     # Mock Treasury
│       └── MockERC20.sol        # Mock ERC20 token
├── script/
│   └── DeployLottery.s.sol      # 部署脚本
├── docs/
│   └── 对接文档.md              # 前端对接文档
└── foundry.toml                 # Foundry 配置
```

## 依赖

- OpenZeppelin Contracts v5.x: `@openzeppelin/contracts`
- Forge Std: `forge-std`

安装依赖：
```bash
forge install OpenZeppelin/openzeppelin-contracts --no-commit
```

## 运行测试

```bash
forge build
forge test -vvv
```

## 测试结果

- **69 tests passed**, 0 failed
- Lottery: 49 tests
- Referral: 20 tests
- 代码覆盖率: Lottery ~90% / Referral ~80%

## 部署到 Sepolia

1. 确保 1 号已部署 VRFConsumer + Treasury，拿到合约地址
2. 填入 `script/DeployLottery.s.sol` 中的地址常量
3. 设置环境变量 `PRIVATE_KEY`
4. 运行：
   ```bash
   forge script script/DeployLottery.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
   ```
5. 部署后联系 1 号执行：
   ```
   vrfConsumer.setConsumerAuthorization(lottery地址, true)
   ```

## 与1号的对接接口

| 接口 | 关键函数 | 用途 |
|------|---------|------|
| `IVRFConsumer` | `requestRandomness(uint32)` → `uint256 requestId` | 请求随机数 |
| `IVRFConsumer` | `retryRequest(uint256)` → `uint256 newRequestId` | 超时重试 |
| `IRandomnessConsumer` | `onRandomnessFulfilled(uint256, uint256[])` | 接收随机数回调 |
| `ITreasury` | `getBetLimits(address)` → `(uint256, uint256)` | 获取下注限额 |
| `ITreasury` | `houseEdgeBps()` → `uint16` | 获取庄家抽水 |
| `ITreasury` | `depositLiquidity(address, uint256)` | 上缴庄家抽水 |

## 1号的网络参数 (Sepolia)

| 参数 | 值 |
|------|-----|
| VRF Coordinator | `0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B` |
| Key Hash | `0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae` |
| Callback Gas Limit | 200,000 |
| House Edge | 250 bps (2.5%) |
| ETH minBet / maxBet | 0.001 ETH / 1 ETH |
