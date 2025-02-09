# 项目介绍

项目采用 solidity v0.8.28 + foundry v0.3.0 + chainlink VRF&Automation 开发，实现一个彩票抽奖的智能合约，用户可以购买彩票，抽奖结果随机生成。

## 项目功能

1、用户购买彩票，定期从奖金池中抽取 1 名幸运者获取全部奖金，随后开启下一轮抽奖。
2、使用 Chainlink VRF 获取随机数
3、使用 chainlink Automation 合约自动化执行抽奖
4、当没有 chainlink 订阅 ID 时，本地模拟创建订阅 ID
5、创建部署助手，通过不同的参数可以部署到不同的链上
6、大量的测试用例，错误信息，和日志信息
7、代码成功部署到测试链上：https://sepolia.etherscan.io/address/0xa4E1C122f747A836D4794567ffbF24A1E72b27d1

## 关于我

github: [https://github.com/xiangguanghua](https://github.com/xiangguanghua)  
email: [ixiangguanghua@163.com](mailto:ixiangguanghua@163.com)  
wechat: GuanghuaXiang
