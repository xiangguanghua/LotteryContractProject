// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/dev/vrf/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/dev/vrf/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

/**
 * @title 实现一个彩票抽奖合约，用户可以购买彩票，抽奖，抽奖结果随机
 * @author XiangGuanghua
 * @notice 彩票抽奖合约
 * @dev 采用Chainlink VRFv2.5实现随机数生成
 *
 * 编码顺序规范:
 * Layout of Contract:
 * - version
 * - imports
 * - errors
 * - interfaces, libraries, contracts
 * - Type declarations
 * - State variables
 * - Events
 * - Modifiers
 * - Functions
 *
 * Layout of Functions:
 * - constructor
 * - receive function (if exists)
 * - fallback function (if exists)
 * - external
 * - public
 * - internal
 * - private
 * - internal & private view & pure functions
 * - external & public view & pure functions
 */
contract Raffle is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    /**
     * Errors***
     */
    error Raffle_SendMoreToEnterRaffle(); // 定义Eth不足错误
    error Raffle_TransferFailed(); // 定义转账失败错误
    error Raffle_RaffleNotOpen(); // 定义抽奖状态错误
    error Raffle_UpkeepNotNeeded(
        // 定义循环错误
        uint256 balance,
        uint256 numPlayers,
        uint256 raffleState
    );

    // Lottery Variables
    uint256 private immutable i_entranceFee; // 彩票面值
    uint256 private immutable i_interval; // 抽奖周期：每过多久选个一个获胜者
    address payable[] private s_players; // 购买彩票的用户地址（可支付的）
    uint256 private s_lastTimestamp; // 记录上次抽奖时间
    address payable private s_winner; // 记录获胜者
    RaffleState private s_raffleState; // 记录抽奖状态
    // 定义抽奖状态

    enum RaffleState {
        OPEN, //  0
        CALCULATING //   1
    }

    // Chainlink VRF Variables
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    /**
     * Events***
     */
    event RaffleEntered(address indexed player); // 定义购买彩票事件，记录购买彩票的用户地址，并且支持使用地址搜索
    event WinnerPicked(address indexed winner); // 定义获胜者事件，记录获胜者地址
    event RequestedRaffeWinner(uint256 indexed requestId); // 定义请求抽奖事件

    // 彩票面值不可变，再构造函数中初始化设置
    constructor(
        uint256 entranceFee, //彩票面值
        uint256 interval, // 抽奖周期
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimestamp = block.timestamp; // 上次抽奖时间
        s_raffleState = RaffleState.OPEN;
    }

    // 购买彩票总奖池金额

    /**
     * 购买彩票
     * 1.用户支付一定数量的ETH
     * 2.购买彩票
     * 3.支付金额进入奖金池中
     * 4.记录购买彩票的用户地址
     */
    function enterRaffle() external payable {
        // 判断用户携带的ETH是否够
        // require(msg.value >= i_entranceFee, "Not enough ETH!!!"); // 错误内容信息需要存储，比较贵，所以改成使用自定义错误类型来判断错误
        // require(msg.value >= i_entranceFee, Raffle_SendMoreToEnterRaffle()); //新版本，使用Require+自定义错误类型来抛出错误，方便代码阅读，但是也贵
        if (msg.value < i_entranceFee) {
            // 如果携带的msg.value不够支付彩票面值，则抛出异常
            revert Raffle_SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            // 抽奖中，不允许购买彩票
            revert Raffle_RaffleNotOpen();
        }
        // 将购买彩票的用户地址存储再用户列表中
        s_players.push(payable(msg.sender)); // 用户可以接受ETH，所以使用payable
        // 触发购买彩票事件，记录购买彩票的用户地址
        emit RaffleEntered(msg.sender);
    }

    /**
     *
     * Chainlink Automation
     * 检查是否需要进行抽奖
     * 1.检查是否过了抽奖时间
     * 2.检查抽奖状态是否为OPEN
     * 3.检查是否有用户购买彩票
     * 4.检查奖金池中是否有金额
     */
    function checkUpkeep(
        bytes memory /*checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory) {
        bool timeHasPassed = (block.timestamp - s_lastTimestamp) > i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    /**
     * Chainlink Automation
     * 随机选出获胜者
     * 1.随机生成一个数
     * 2.使用随机数选择一个获胜者
     * 3.将奖金池中的金额发送给获胜者
     */
    function performUpkeep(bytes calldata /*performData*/) external {
        // 计算选取获胜者的时间间隔
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        // 设置抽奖状态为计算中
        s_raffleState = RaffleState.CALCULATING;

        // 从chainlink VRF v2.5中获取随机数
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId, //订阅ID
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffeWinner(requestId);
    }

    /**
     * Chainlink VRF 回调函数
     */
    function fulfillRandomWords(
        uint256,
        /*requestId*/ uint256[] memory randomWords
    ) internal override {
        // 获取随机数
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        // 获取获胜者
        address payable winner = s_players[indexOfWinner];
        s_winner = winner; // 将获胜者地址赋值给s_winner
        // 将抽奖状态设置为OPEN
        s_raffleState = RaffleState.OPEN;
        // 清空购买彩票的用户列表
        s_players = new address payable[](0);
        // 更新上次抽奖时间
        s_lastTimestamp = block.timestamp;

        // 将奖金池中的金额发送给获胜者
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFailed();
        }
        emit WinnerPicked(winner);
    }

    /**
     * 一些Getter方法**********************
     */
    /**
     * 获取彩票面值
     */
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimestamp;
    }

    function getRecentWinner() public view returns (address) {
        return s_winner;
    }
}

/**
 * 编码顺序规范***************
 */
/**
 * Layout of Contract************
 */
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

/**
 * Layout of Functions************
 */
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions
