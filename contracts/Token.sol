pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./ReentrancyGuard.sol" as ReentrancyGuard;
import "./NFTToken.sol";
import "./VestingToken.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";


contract Token is Ownable {

    struct Loan {
        address borrower;
        uint256 amount;
        uint256 interestRate; // En pourcentage (ex: 10 pour 10%)
        uint256 duration; // En nombre de blocs
        uint256 startBlock;
        bool isActive;
    }

    using SafeMath for uint256;
    
    NFTToken public nftContract;
    VestingToken public vestingContract;

    mapping(uint256 => Loan) public loans;
    uint256 public nextLoanId = 1;

    mapping(uint256 => uint256) public nftPrices;

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

    // Fonction pour limiter le montant de tokens qu'un détenteur peut transférer
    uint256 public maxTransferAmountPercentage = 1; // Limite à 1%
    
    constructor(address _routerAddress, address _nftAddress, address _vestingAddress) {
        vestingContract = VestingToken(_vestingAddress);

        // Initialiser le contrat de NFT
        nftContract = NFTToken(_nftAddress);

        // Initialiser Uniswap router et factory
        uniswapRouter = IUniswapV2Router02(_routerAddress);
        uniswapFactory = IUniswapV2Factory(uniswapRouter.factory());

        balances[msg.sender] = totalSupply;
        admin = msg.sender;
        transfersPaused = false;
    }

    function setMaxTransferAmountPercentage(uint256 percentage) public onlyOwner {
        maxTransferAmountPercentage = percentage;
    }

    function _getMaxTransferAmount(address sender) internal view returns (uint256) {
        return balances[sender].mul(maxTransferAmountPercentage).div(100);
    }

    function createVestingSchedule(address beneficiary, uint256 startTimestamp, uint256 endTimestamp, uint256 totalAmount) public onlyOwner {
        require(isValidAddress(beneficiary), "Invalid beneficiary address");
        require(startTimestamp < endTimestamp, "Invalid schedule duration");
        require(totalAmount > 0, "Invalid amount");

        // Appeler la fonction du contrat VestingToken
        vestingContract.createVestingSchedule(beneficiary, startTimestamp, endTimestamp, totalAmount);
         // Appeler la fonction de retrait des tokens vestés
        vestingContract.withdrawVestedTokens();
    }
    
    function withdrawVestedTokens() public {
        VestingToken(vestingContract).withdrawVestedTokens();
    }


    //Loan transaction
    function createLoan(uint256 amount, uint256 interestRate, uint256 duration) public {
        require(amount > 0, "Invalid loan amount");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        uint256 startBlock = block.number;
        Loan memory newLoan = Loan({
            borrower: msg.sender,
            amount: amount,
            interestRate: interestRate,
            duration: duration,
            startBlock: startBlock,
            isActive: true
        });

        loans[nextLoanId++] = newLoan;

        // Transfère les tokens empruntés au contrat
        transferFrom(msg.sender, address(this), amount);
    }

    function borrow(uint256 loanId) public {
        Loan storage loan = loans[loanId];

        require(loan.isActive, "Loan not available");
        require(loan.borrower != msg.sender, "Cannot borrow your own loan");

        uint256 interestAmount = loan.amount * loan.interestRate / 100;
        uint256 totalAmountToRepay = loan.amount + interestAmount;

        // Vérifie que l'emprunteur a suffisamment de tokens pour rembourser le prêt
        require(balanceOf(msg.sender) >= totalAmountToRepay, "Insufficient balance");

        // Transfère les tokens au demandeur de prêt
        transfer(loan.borrower, loan.amount);

        // Désactive le prêt
        loan.isActive = false;
    }

    function repayLoan(uint256 loanId) public {
        Loan storage loan = loans[loanId];
        require(loan.isActive, "Loan not available");
        require(loan.borrower == msg.sender, "You are not the borrower");

        uint256 interestAmount = loan.amount * loan.interestRate / 100;
        uint256 totalAmountToRepay = loan.amount + interestAmount;

        // Vérifie que l'emprunteur a suffisamment de tokens pour rembourser le prêt
        require(balanceOf(msg.sender) >= totalAmountToRepay, "Insufficient balance");

        // Transfère les tokens au contrat (remboursement)
        transferFrom(msg.sender, address(this), totalAmountToRepay);

        // Active la possibilité de réemprunter
        loan.isActive = true;
    }

    // Fonction pour créer un NFT
    function createNFT(address to, uint256 tokenId) external onlyOwner {
        nftContract.mint(to, tokenId);
    }

    function buyNFT(uint256 tokenId) public payable {
        require(nftContract.ownerOf(tokenId) != address(0), "Invalid token");
        require(msg.value >= nftPrices[tokenId], "Insufficient funds");
        
        address owner = nftContract.ownerOf(tokenId);
        nftContract.safeTransferFrom(owner, msg.sender, tokenId);
        payable(owner).transfer(msg.value);
    }

    function putNFTForSale(uint256 tokenId, uint256 price) public {
        require(nftContract.ownerOf(tokenId) == msg.sender, "Not the owner");
        require(price > 0, "Price must be greater than 0");
        
        nftPrices[tokenId] = price;
    }

    function buyNFTFromSale(uint256 tokenId) public payable {
        require(nftContract.tokenExists(tokenId), "Invalid token");
        require(nftPrices[tokenId] > 0, "NFT not for sale");
        require(msg.value >= nftPrices[tokenId], "Insufficient funds");
        
        address owner = nftContract.ownerOf(tokenId);
        nftContract.safeTransferFrom(owner, msg.sender, tokenId);
        payable(owner).transfer(msg.value);
        nftPrices[tokenId] = 0;
    }

    function removeFromSale(uint256 tokenId) public {
        require(nftContract.ownerOf(tokenId) == msg.sender, "Not the owner");
        nftPrices[tokenId] = 0;
    }

    function getNFTsForSale() public view returns (uint256[] memory) {
        uint256[] memory tokensForSale = new uint256[](nftContract.totalNFTs());

        uint256 count = 0;
        for (uint256 tokenId = 0; tokenId < nftContract.totalNFTs(); tokenId++) {
            if (nftContract.ownerOf(tokenId) == address(this)) {
                tokensForSale[count] = tokenId;
                count++;
            }
        }
        return tokensForSale;
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
        require(value <= _getMaxTransferAmount(msg.sender), "Transfer amount exceeds limit");
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