// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract Token is Ownable, ReentrancyGuard{

    using SafeMath for uint256;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => mapping(address => uint256)) public allowanceExpiry;
    mapping(address => address) public delegates; // Mapping des délégués
    mapping(address => uint256) public stakedBalances; // Solde de tokens bloqués
    mapping(address => uint256) public rewards; // Récompenses gagnées

    uint256 public stakingStartBlock; // Bloc de début du staking
    uint256 public stakingEndBlock; // Bloc de fin du staking

    uint256 public totalSupply = 26000000 * 10 ** 18;

    string public name = "HumanCoin";
    string public symbol = "HC";

    uint8 public decimals = 18;

    address public admin; // Nouvelle variable pour stocker l'adresse de l'administrateur

    bool public transfersPaused;
    bool public approvalsPaused;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TokensBurned(address indexed burner, uint256 value); // Événement pour le brûlage

    IUniswapV2Router02 public uniswapRouter;
    IUniswapV2Factory public uniswapFactory;
    
    constructor(address _routerAddress) {
        // Initialize Uniswap router and factory
        uniswapRouter = IUniswapV2Router02(_routerAddress);
        uniswapFactory = IUniswapV2Factory(uniswapRouter.factory());

        balances[msg.sender] = totalSupply;
        admin = msg.sender;
        transfersPaused = false;
    }
    
    // Fonction pour ajouter de la liquidité via Uniswap
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) external onlyOwner {
        address tokenAddress = address(this);

        // Approve token transfer to Uniswap router
        approve(address(uniswapRouter), tokenAmount);

        // Swap tokens for ETH
        uniswapRouter.swapExactTokensForETH(
            tokenAmount,
            0, // Min amount ETH expected (set to 0)
            getPathForTokenToEth(),
            address(this),
            block.timestamp + 3600
        );

        // Add liquidity to Uniswap
        uniswapRouter.addLiquidityETH{value: ethAmount}(
            tokenAddress,
            tokenAmount,
            tokenAmount,
            ethAmount,
            msg.sender, // Recevoir les tokens LP
            block.timestamp + 3600
        );
    }
    
    function getPathForTokenToEth() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapRouter.WETH();
        return path;
    }

    function approve(address spender, uint256 value, uint256 expiry) public notPaused returns (bool) {
        require(isValidAddress(spender), "Invalid spender address");
        require(value > 0, "Invalid approval value");
        allowance[msg.sender][spender] = value;
        allowanceExpiry[msg.sender][spender] = expiry;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    modifier notExpired(address owner, address spender) {
        require(allowanceExpiry[owner][spender] == 0 || block.timestamp <= allowanceExpiry[owner][spender], "Allowance expired");
        _;
    }

    modifier notPaused() {
        require(!transfersPaused, "Transfers are paused");
        require(!approvalsPaused, "Approvals are paused");
        _;
    }

    function pauseApprovals() public onlyOwner {
        approvalsPaused = true;
    }

    function unpauseApprovals() public onlyOwner {
        approvalsPaused = false;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this");
        _;
    }
    
    function isValidAddress(address _address) internal pure returns (bool) {
        return _address != address(0);
    }


    function delegateVote(address delegate) public notPaused returns (bool) {
        require(delegate != address(0), "Invalid delegate address");
        delegates[msg.sender] = delegate;
        return true;
    }

    function getCurrentDelegate(address user) public view returns (address) {
        return delegates[user];
    }

    function balanceOf(address owner) public view returns (uint256) {
        return balances[owner];
    }

    function transfer(address to, uint256 value) public notPaused returns (bool) {
        require(balances[msg.sender] >= value, 'balance too low');
        balances[msg.sender] = balances[msg.sender].sub(value);
        balances[to] = balances[to].add(value);
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public notPaused returns (bool) {
        require(balances[from] >= value, 'balance too low');
        require(allowance[from][msg.sender] >= value, 'allowance too low');
        balances[from] = balances[from].sub(value);
        balances[to] = balances[to].add(value);
        allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public notPaused returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function burnTokens(uint256 value) public onlyAdmin {
        require(value > 0, "Value must be greater than 0");
        require(balances[msg.sender] >= value, "Not enough balance");
        balances[msg.sender] = balances[msg.sender].sub(value);
        totalSupply = totalSupply.sub(value);
        emit TokensBurned(msg.sender, value);
    }

    function pauseTransfers() public onlyAdmin {
        transfersPaused = true;
    }

    function unpauseTransfers() public onlyAdmin {
        transfersPaused = false;
    }
        function startStaking(uint256 duration) public onlyOwner {
        stakingStartBlock = block.number;
        stakingEndBlock = block.number.add(duration);
    }

    function stakeTokens(uint256 amount) public notPaused {
        require(stakingStartBlock > 0 && block.number <= stakingEndBlock, "Staking not active");
        require(amount > 0, "Invalid staking amount");
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] = balances[msg.sender].sub(amount);
        stakedBalances[msg.sender] = stakedBalances[msg.sender].add(amount);
    }

    function claimRewards() public notPaused {
        require(block.number > stakingEndBlock, "Staking not ended yet");
        uint256 reward = calculateReward(msg.sender);
        rewards[msg.sender] = rewards[msg.sender].add(reward);
    }

    function withdrawStake() public notPaused {
        require(block.number > stakingEndBlock, "Staking not ended yet");
        uint256 stakedAmount = stakedBalances[msg.sender];
        require(stakedAmount > 0, "No staked tokens");
        uint256 reward = calculateReward(msg.sender);
        rewards[msg.sender] = rewards[msg.sender].add(reward);
        stakedBalances[msg.sender] = 0;
        balances[msg.sender] = balances[msg.sender].add(stakedAmount);
    }

    function calculateReward(address user) internal view returns (uint256) {
        uint256 stakedAmount = stakedBalances[user];
        if (stakedAmount == 0) {
            return 0;
        }

        uint256 stakingDuration = stakingEndBlock.sub(stakingStartBlock);
        uint256 blocksStaked = block.number.sub(stakingStartBlock);

        uint256 totalRewards = 10000 * 10 ** 18;

        uint256 reward = stakedAmount * totalRewards * blocksStaked / stakingDuration / totalSupply;
        
        return reward;
    }
}