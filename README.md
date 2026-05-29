# Use-EIP712: EIP-712 链下签名授权与白名单设计

基于 Foundry + OpenZeppelin 实现的 EIP-712 链下签名项目，包含 EIP-2612 Permit Token、TokenBank 离线授权存款、以及基于白名单签名的 NFT 市场。

## 项目概述

本项目演示如何使用 EIP-712 结构化签名标准，实现以下功能：

1. **EIP-2612 Permit Token** — 支持离线签名授权的 ERC20 Token（LYToken）
2. **TokenBank 离线存款** — 通过 `permitDeposit()` 实现无 Gas 审批的存款
3. **NFT 白名单购买** — 只有获得项目方离线签名的白名单地址才能购买 NFT

## 核心架构

```
┌──────────────────────────────────────────────────────────────┐
│                        EIP-712 签名流程                        │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Permit 存款流程                                           │
│  ┌─────────┐   签名 Permit    ┌─────────┐   permitDeposit()  │
│  │  Alice  │ ──────────────► │  Relayer │ ───────────────►   │
│  │(Token   │                  │  (Bob)   │    TokenBank       │
│  │ owner)  │                  │          │                    │
│  └─────────┘                  └─────────┘                    │
│                                                              │
│  2. 白名单购买流程                                            │
│  ┌─────────┐ 签名 Whitelist  ┌─────────┐   permitBuy()      │
│  │  Owner  │ ──────────────► │  Buyer   │ ───────────────►   │
│  │(项目方) │                  │(白名单)  │   NFTMarket        │
│  └─────────┘                  └─────────┘                    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## 合约说明

### LYToken.sol — EIP-2612 Permit Token

基于 OpenZeppelin 的 `ERC20` + `ERC20Permit` 扩展，支持：
- 标准 ERC20 转账、授权
- EIP-2612 `permit()` 离线签名授权（无需先发 approve 交易）
- Token 铸造和销毁

### TokenBank.sol — Token 存款银行

| 函数 | 说明 |
|------|------|
| `deposit(uint256)` | 传统存款（需先 approve） |
| `permitDeposit(address,uint256,uint256,uint8,bytes32,bytes32)` | EIP-712 离线签名存款（免 approve 交易） |
| `withdraw(uint256)` | 提取存款 |

### LYNFT.sol — ERC-721 NFT

基于 OpenZeppelin 的 `ERC721` + `ERC721Enumerable` + `ERC721URIStorage` 扩展。

### NFTMarket.sol — 白名单 NFT 市场

| 函数 | 说明 |
|------|------|
| `list(uint256,uint256)` | 上架 NFT |
| `buy(uint256)` | 普通购买 |
| `permitBuy(address,uint256,uint256,uint256,uint8,bytes32,bytes32)` | 白名单签名购买 |
| `delist(uint256)` | 下架 NFT |

白名单签名数据结构（EIP-712 typed data）：
```solidity
WhitelistPermit(address buyer, uint256 tokenId, uint256 price, uint256 deadline)
```

## 快速开始

### 环境要求

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (>= 1.7.0)
- Solidity 0.8.24

### 安装依赖

```bash
git clone https://github.com/1952154539/use-EIP712.git
cd use-EIP712
forge install
```

### 编译合约

```bash
forge build
```

### 运行测试

```bash
forge test -vvv
```

### 运行单个测试

```bash
# 测试 Permit 存款
forge test --match-test test_PermitDeposit_Success -vvv

# 测试白名单 NFT 购买
forge test --match-test test_PermitBuy_Success -vvv

# 测试多笔白名单购买
forge test --match-test test_FullFlow_MultiplePermitBuys -vvv
```

## 测试用例

| 测试用例 | 说明 |
|----------|------|
| `test_PermitDeposit_Success` | 使用 Permit 签名成功存款 |
| `test_PermitDeposit_ExpiredPermit` | 过期的 Permit 签名被拒绝 |
| `test_PermitDeposit_WrongSigner` | 错误的签名者被拒绝 |
| `test_PermitDeposit_ThenWithdraw` | 存款后提取 |
| `test_TraditionalDeposit` | 传统 approve + deposit 流程 |
| `test_PermitBuy_Success` | 白名单签名购买成功 |
| `test_PermitBuy_NotWhitelisted` | 非白名单地址被拒绝 |
| `test_PermitBuy_ExpiredPermit` | 过期白名单签名被拒绝 |
| `test_PermitBuy_ReplayAttack` | 签名重放攻击防护 |
| `test_PermitBuy_WrongBuyer` | 签名与买家不匹配被拒绝 |
| `test_PermitBuy_PriceMismatch` | 价格不匹配被拒绝 |
| `test_FullFlow_MultiplePermitBuys` | 多用户多次白名单购买完整流程 |

### 测试运行结果

```
Ran 12 tests for test/EIP712.t.sol:EIP712Test
[PASS] test_FullFlow_MultiplePermitBuys()
[PASS] test_PermitBuy_ExpiredPermit()
[PASS] test_PermitBuy_NotWhitelisted_Reverts()
[PASS] test_PermitBuy_PriceMismatch()
[PASS] test_PermitBuy_ReplayAttack()
[PASS] test_PermitBuy_Success()
[PASS] test_PermitBuy_WrongBuyer()
[PASS] test_PermitDeposit_ExpiredPermit()
[PASS] test_PermitDeposit_Success()
[PASS] test_PermitDeposit_ThenWithdraw()
[PASS] test_PermitDeposit_WrongSigner()
[PASS] test_TraditionalDeposit()
Suite result: ok. 12 passed; 0 failed; 0 skipped
```

## EIP-712 签名流程说明

### Permit 离线授权存款

1. Token 持有者（Alice）在链下对 Permit 数据进行签名
   - 签名内容：`Permit(owner=Alice, spender=TokenBank, value=1000, nonce=n, deadline=...)`
2. 任何人都可以（如 Bob/Relayer）调用 `permitDeposit()` 提交签名
3. 合约验证签名有效性后，直接从 Alice 账户划转 Token
4. Alice 无需先发 `approve` 交易，节省 Gas

### 白名单 NFT 购买

1. 项目方（Owner）在链下为白名单地址签名
   - 签名内容：`WhitelistPermit(buyer=白名单地址, tokenId=0, price=100, deadline=...)`
2. 白名单用户调用 `permitBuy()` 提交签名
3. 合约验证签名由项目方签发且未过期/未使用
4. 验证通过后执行 NFT 转移和付款

## 安全特性

- EIP-712 结构化签名，防止签名跨合约重放
- `deadline` 过期机制
- `usedPermits` 防止同一签名重复使用
- 签名与买家地址绑定，防止冒用
- 签名与价格绑定，防止价格篡改

## 参考资源

- [EIP-2612: Permit Extension for ERC-20](https://eips.ethereum.org/EIPS/eip-2612)
- [EIP-712: Typed structured data hashing and signing](https://eips.ethereum.org/EIPS/eip-712)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/5.x/)
- [Foundry Book](https://book.getfoundry.sh/)
- [TokenBank EIP-712 参考项目](https://github.com/lbc-team/TokenBank/tree/tokenbank-eip712)

## License

MIT
