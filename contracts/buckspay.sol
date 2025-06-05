// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BuckspayV4 is ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    address public owner;
    uint256 public totalTxs;

    uint32 private totalFree = 2592000;
    uint16 public profit = 0;

    bytes32 public constant USERS_BASE_ROLE = keccak256("USERS_BASE_ROLE");
    bytes32 public constant USERS_LIQUIDATOR_ROLE = keccak256("USERS_LIQUIDATOR_ROLE");
    bytes32 public constant USERS_FROG_ROLE = keccak256("USERS_FROG_ROLE");
    mapping(address => address) public busy;
    mapping(address => uint256) public balance;
    mapping(address => userStruct) public transfers;
    mapping(address => uint32) public _usersLimit;

    struct userStruct {
        address[] users;
        uint256 amount;
        uint256 utility;
    }
    
    enum TypeTransaction {
        Deposit,
        TransferConfirmed,
        TransferCanceled
    }
    event Transaction(
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        TypeTransaction typeTrx
    );
    event UpdateList(
        address indexed account,
        bool status,
        TypeTransaction typeUpdate
    );
    event Withdrawal(address indexed receiver, uint256 amount);
    event ProfitUpdated(uint16 oldProfit, uint16 newProfit);

    constructor(
        address _token,
        address[] memory _frogs,
        address[] memory _liquidators,
        address[] memory users
    ) {
        require(_token != address(0), "Invalid token address");
        require(_frogs.length <= 100, "Too many frogs");
        require(_liquidators.length <= 100, "Too many liquidators");
        require(users.length <= 100, "Too many users");
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        owner = msg.sender;
        token = IERC20(_token);
        for (uint i = 0; i < _frogs.length; i++) {
            _grantRole(USERS_FROG_ROLE, _frogs[i]);
        }
        for (uint i = 0; i < _liquidators.length; i++) {
            _grantRole(USERS_LIQUIDATOR_ROLE, _liquidators[i]);
        }
        for (uint i = 0; i < users.length; i++) {
            _grantRole(USERS_BASE_ROLE, users[i]);
            _usersLimit[users[i]] = uint32(block.timestamp) + totalFree;
        }
    }

    modifier onlyUserAvailable(address[] memory friends) {
        require(friends.length <= 50, "Too many friends");
        require(hasRole(USERS_BASE_ROLE, msg.sender), "Sender must be a registered user");
        for (uint i = 0; i < friends.length; i++) {
            require(hasRole(USERS_BASE_ROLE, friends[i]), "One or more friends are not registered users");
        }
        _;
    }

    function deposit(
        uint256 _amount,
        address _receiver,
        address[] memory friends
    ) external nonReentrant whenNotPaused onlyUserAvailable(friends) onlyRole(USERS_FROG_ROLE) {
        require(_amount > 0, "Amount must be greater than zero");
        require(_receiver != address(0), "Receiver address cannot be zero");
        require(hasRole(USERS_LIQUIDATOR_ROLE, _receiver), "Only the liquidators can liquidate");
        require(
            transfers[_receiver].users.length == 0,
            "Liquidator in a process"
        );
        address[] memory users = new address[](friends.length);
        uint256 utility = 0;
        if (_usersLimit[friends[0]] < block.timestamp) {
            utility = uint256(_amount * profit / 10000);
        }
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
            token.safeTransferFrom(friends[i], address(this), _valueTransfer);
        }
        transfers[_receiver] = userStruct({
            users: users,
            amount: (_amount * friends.length),
            utility: (utility * friends.length)
        });
        emit Transaction(friends[0], _receiver, _amount, TypeTransaction.Deposit);
        totalTxs += 1;
    }

    function confirm() external whenNotPaused {
        _confirm(msg.sender);
    }

    function confirmFrog(address _sender) external whenNotPaused onlyRole(USERS_FROG_ROLE) {
        uint256 utility = _confirm(_sender);
        distributeTax(utility);
    }

    function distributeTax(uint256 utility) private {
        if (utility > 0) {
            uint256 tax = uint256(utility / 2);
            require(balance[owner] >= tax, "Not enough balance for tax distribution");
            balance[owner] -= tax;
            balance[msg.sender] += tax;
        }
    }

    function _confirm(address _sender) private nonReentrant returns (uint256) {
        address _receiver = busy[_sender];
        userStruct memory transferData = transfers[_receiver];
        uint256 _amount = transferData.amount;
        require(_amount > 0, "No funds available");
        token.safeTransfer(_receiver, _amount);
        delete transfers[_receiver];
        for (uint i = 0; i < transferData.users.length; i++) {
            delete busy[transferData.users[i]];
        }
        emit Transaction(_sender, _receiver, _amount, TypeTransaction.TransferConfirmed);
        return transferData.utility;
    }

    function cancel(address _sender) external whenNotPaused nonReentrant {
        address _receiver = busy[_sender];
        require(hasRole(USERS_FROG_ROLE, msg.sender) || msg.sender == _receiver, "Only frogs or receiver can call this function");
        address[] memory _users = transfers[_receiver].users;
        uint256 _amount = transfers[_receiver].amount;
        require(_amount > 0, "No funds available");
        token.safeTransfer(_sender, _amount);
        uint256 utility = transfers[_receiver].utility;
        delete transfers[_receiver];
        for (uint i = 0; i < _users.length; i++) {
            delete busy[_users[i]];
        }
        emit Transaction(_sender, _receiver, _amount, TypeTransaction.TransferCanceled);
        distributeTax(utility);
    }

    function withdraw(uint256 _balance) external nonReentrant {
        require(token.balanceOf(address(this)) >= _balance, "Contract does not have enough tokens");
        require(balance[msg.sender] >= _balance, "No funds available");
        balance[msg.sender] -= _balance;
        token.safeTransfer(msg.sender, _balance);
        emit Withdrawal(msg.sender, _balance);
    }

    function addFrog(address[] calldata _frogs) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint i = 0; i < _frogs.length; i++) {
            _grantRole(USERS_FROG_ROLE, _frogs[i]);
        }
    }

    function removeFrogs(address[] calldata _frogs) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint i = 0; i < _frogs.length; i++) {
            _revokeRole(USERS_FROG_ROLE, _frogs[i]);
        }
    }

    function addUsers(address[] calldata _users) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint i = 0; i < _users.length; i++) {
            _grantRole(USERS_BASE_ROLE, _users[i]);
            _usersLimit[_users[i]] = uint32(block.timestamp) + totalFree;
        }
    }

    function removeUsers(address[] calldata _users) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint i = 0; i < _users.length; i++) {
            require(
                busy[_users[i]] == address(0),
                "User is busy in a transaction"
            );
            _revokeRole(USERS_BASE_ROLE, _users[i]);
            delete _usersLimit[_users[i]];
        }
    }

    function addLiquidator(address[] calldata _liquidators) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint i = 0; i < _liquidators.length; i++) {
            _grantRole(USERS_LIQUIDATOR_ROLE, _liquidators[i]);
        }
    }

    function removeLiquidator(
        address[] calldata _liquidators
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint i = 0; i < _liquidators.length; i++) {
            _revokeRole(USERS_LIQUIDATOR_ROLE, _liquidators[i]);
        }
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function updateProfit(uint16 newProfit) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(newProfit <= 2000, "Profit too high");
        emit ProfitUpdated(profit, newProfit);
        profit = newProfit;
    }
}