// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract Liquidator is ReentrancyGuard {
    IERC20 public token;
    address public owner;
    uint256 public totalTxs;
    bool public paused;
    uint8 public profit = 0;
    mapping(address => bool) public frogs;
    mapping(address => uint256) public balance;
    mapping(address => bool) public liquidators;
    mapping(address => address) public busy;
    struct userStruct {
        address[] users;
        uint256 amount;
        uint256 utility;
    }
    mapping(address => userStruct) public transfers;

    event Deposit(
        address indexed depositor,
        address indexed receiver,
        uint256 amount
    );
    event Withdrawal(address indexed receiver, uint256 amount);
    event TransferConfirmed(
        address indexed sender,
        address indexed receiver,
        uint256 amount
    );
    event TransferCancelled(
        address indexed sender,
        address indexed receiver,
        uint256 amount
    );
    event ProfitUpdated(uint8 oldProfit, uint8 newProfit);
    event Paused(address account, bool status);
    event Frogs(address account, bool status);
    event Liquidators(address account, bool status);

    constructor(
        address _token,
        address[] memory _frogs,
        address[] memory _liquidators
    ) {
        owner = msg.sender;
        for (uint i = 0; i < _frogs.length; i++) {
            frogs[_frogs[i]] = true;
        }
        for (uint i = 0; i < _liquidators.length; i++) {
            liquidators[_liquidators[i]] = true;
        }
        token = IERC20(_token);
    }

    modifier onlyFrogs() {
        require(frogs[msg.sender], "Only the frogs can call this function");
        _;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Only the owner can call this function");
        _;
    }

    modifier isPaused() {
        require(paused == false, "This contract is paused by owner");
        _;
    }

    function updateProfit(uint8 newProfit) external onlyOwner {
        emit ProfitUpdated(profit, newProfit);
        profit = newProfit;
    }

    function deposit(
        uint256 _amount,
        address _receiver,
        address[] memory friends
    ) external nonReentrant isPaused {
        require(_receiver != address(0), "Receiver address cannot be zero");
        require(liquidators[_receiver], "Only the liquidators can liquidate");
        require(
            transfers[_receiver].users.length == 0,
            "Liquidator in a process"
        );
        address[] memory users = new address[](friends.length);
        // uint256 amount = _amount * friends.length;
        uint256 utility = uint256(_amount * profit / 1000);
        uint256 _valueTransfer = _amount + utility;
        balance[owner] += (utility * friends.length);
        for (uint i = 0; i < friends.length; i++) {
            require(friends[i] != address(0), "Sender address cannot be zero");
            require(
                busy[friends[i]] == address(0),
                "User is busy in other transaction"
            );
            users[i] = friends[i];
            busy[friends[i]] = _receiver;
            bool transferSuccess = token.transferFrom(
                friends[i],
                address(this),
                _valueTransfer
            );
            require(transferSuccess, "Transfer to contract failed");
        }
        transfers[_receiver] = userStruct({
            users: users,
            amount: (_amount * friends.length),
            utility: (utility * friends.length)
        });
        totalTxs += 1;
        emit Deposit(msg.sender, _receiver, _amount);
    }

    function confirm() external isPaused {
        _confirm(msg.sender);
    }

    function confirmFrog(address _sender) external isPaused onlyFrogs {
        uint256 utility = _confirm(_sender);
        distributeTax(utility);
    }

    function distributeTax(uint256 utility) private {
        if (utility > 0) {
            uint256 tax = uint256(utility / 2);
            balance[owner] -= tax;
            balance[msg.sender] += tax;
        }
    }

    function _confirm(address _sender) private nonReentrant returns (uint256) {
        address _receiver = busy[_sender];
        address[] memory _users = transfers[_receiver].users;
        uint256 _amount = transfers[_receiver].amount;
        require(_amount > 0, "No funds available");
        bool transferSuccess = token.transfer(_receiver, _amount);
        delete transfers[_receiver];
        for (uint i = 0; i < _users.length; i++) {
            delete busy[_users[i]];
        }
        require(transferSuccess, "Transfer failed");
        emit TransferConfirmed(_sender, _receiver, _amount);
        return transfers[_receiver].utility;
    }

    function cancel(address _sender) external isPaused onlyFrogs nonReentrant {
        address _receiver = busy[_sender];
        address[] memory _users = transfers[_receiver].users;
        // receiverStruct memory _receiver = transfers[_sender];
        uint256 _amount = transfers[_receiver].amount;
        require(_amount > 0, "No funds available");
        bool transferSuccess = token.transfer(_sender, _amount);
        delete transfers[_receiver];
        for (uint i = 0; i < _users.length; i++) {
            delete busy[_users[i]];
        }
        emit TransferCancelled(_sender, _receiver, _amount);
        require(transferSuccess, "Transfer failed");
        distributeTax(transfers[_receiver].utility);
    }

    function withdraw(uint256 _balance) external nonReentrant {
        require(balance[msg.sender] >= _balance, "No funds available");
        balance[msg.sender] -= _balance;
        bool transferSuccess = token.transfer(msg.sender, _balance);
        require(transferSuccess, "Transfer to contract failed");
        emit Withdrawal(msg.sender, _balance);
    }

    function addFrog(address[] calldata _frogs) external onlyOwner {
        for (uint i = 0; i < _frogs.length; i++) {
            emit Frogs(_frogs[i], true);
            frogs[_frogs[i]] = true;
        }
    }

    function removeFrogs(address[] calldata _frogs) external onlyOwner {
        for (uint i = 0; i < _frogs.length; i++) {
            emit Frogs(_frogs[i], false);
            delete frogs[_frogs[i]];
        }
    }

    function addLiquidator(address[] calldata _liquidators) external onlyOwner {
        for (uint i = 0; i < _liquidators.length; i++) {
            emit Liquidators(_liquidators[i], true);
            liquidators[_liquidators[i]] = true;
        }
    }

    function removeLiquidator(
        address[] calldata _liquidators
    ) external onlyOwner {
        for (uint i = 0; i < _liquidators.length; i++) {
            emit Liquidators(_liquidators[i], false);
            delete liquidators[_liquidators[i]];
        }
    }

    function pauseContract() external onlyOwner {
        emit Paused(msg.sender, !paused);
        paused = !paused;
    }
}