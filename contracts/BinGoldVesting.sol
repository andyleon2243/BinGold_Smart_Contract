// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./IBinGold.sol";

/**
 * @title BinGoldVesting
 * @dev A simplified contract for managing the vesting schedules for BinGold token allocations
 * Specifically handles vesting for team members and advisors only.
 */
contract BinGoldVesting is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{
    using SafeERC20Upgradeable for IBinGold;

    // BinGold token contract
    IBinGold public binGoldToken;

    // Allocation amounts
    uint256 public TEAM_ALLOCATION; // 20% (500,000 BIGOD)
    uint256 public ADVISOR_ALLOCATION; // 5% (125,000 BIGOD)

    // Vesting durations
    uint256 public constant MONTH = 30 days;
    uint256 public constant TEAM_CLIFF = 6 * MONTH;
    uint256 public constant TEAM_VESTING_DURATION = 36 * MONTH;
    uint256 public constant ADVISOR_CLIFF = 0;
    uint256 public constant ADVISOR_VESTING_DURATION = 12 * MONTH;

    // Vesting start time
    uint256 public vestingStartTime;

    // Beneficiary addresses
    address public teamWallet;
    address public advisorWallet;

    // Released amounts tracking
    uint256 public teamTokensReleased;
    uint256 public advisorTokensReleased;

    // Events
    event TokenAddressUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event WalletUpdated(string role, address oldWallet, address newWallet);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializer function (replaces constructor for upgradeable contracts)
     */
    function initialize(
        address _binGoldToken,
        uint256 _startTime,
        address _teamWallet,
        address _advisorWallet
    ) external initializer {
        require(_binGoldToken != address(0), "Token address cannot be zero");

        require(
            _startTime >= block.timestamp,
            "Start time must be in the future"
        );
        require(_teamWallet != address(0), "Team wallet cannot be zero");
        require(_advisorWallet != address(0), "Advisor wallet cannot be zero");

        // Initialize parent contracts in the correct order
        __ReentrancyGuard_init();
        __Ownable_init();

        binGoldToken = IBinGold(_binGoldToken);

        
        uint256 decimals = IBinGold(_binGoldToken).decimals();
        TEAM_ALLOCATION = 500000 * 10 ** decimals;
        ADVISOR_ALLOCATION = 125000 * 10 ** decimals;


        vestingStartTime = _startTime;
        teamWallet = _teamWallet;
        advisorWallet = _advisorWallet;

        teamTokensReleased = 0;
        advisorTokensReleased = 0;
    }

    /**
     * @dev Update the team wallet address
     * @param _newTeamWallet The new team wallet address
     */
    function updateTeamWallet(address _newTeamWallet) external onlyOwner {
        require(_newTeamWallet != address(0), "New team wallet cannot be zero");
        address oldTeamWallet = teamWallet;
        teamWallet = _newTeamWallet;
        emit WalletUpdated("TEAM", oldTeamWallet, _newTeamWallet);
    }

    /**
     * @dev Update the advisor wallet address
     * @param _newAdvisorWallet The new advisor wallet address
     */
    function updateAdvisorWallet(address _newAdvisorWallet) external onlyOwner {
        require(
            _newAdvisorWallet != address(0),
            "New advisor wallet cannot be zero"
        );
        address oldAdvisorWallet = advisorWallet;
        advisorWallet = _newAdvisorWallet;
        emit WalletUpdated("ADVISOR", oldAdvisorWallet, _newAdvisorWallet);
    }

    /**
     * @dev Update the token contract address
     * @param _newTokenAddress The new token contract address
     */
    function updateTokenAddress(address _newTokenAddress) external onlyOwner {
        require(
            _newTokenAddress != address(0),
            "New token address cannot be zero"
        );
        address oldTokenAddress = address(binGoldToken);
        binGoldToken = IBinGold(_newTokenAddress);
        emit TokenAddressUpdated(oldTokenAddress, _newTokenAddress);
    }

    /**
     * @dev Calculate releasable tokens for a beneficiary
     * @param _beneficiary Address of the beneficiary
     * @return Amount of releasable tokens
     */
    function calculateReleasableAmount(
        address _beneficiary
    ) public view returns (uint256) {
        // Check if the address is the team wallet or advisor wallet
        if (_beneficiary != teamWallet && _beneficiary != advisorWallet) {
            return 0;
        }

        uint256 totalAllocation;
        uint256 releasedAmount;
        uint256 cliff;
        uint256 vestingDuration;

        if (_beneficiary == teamWallet) {
            totalAllocation = TEAM_ALLOCATION;
            releasedAmount = teamTokensReleased;
            cliff = TEAM_CLIFF;
            vestingDuration = TEAM_VESTING_DURATION;
        } else {
            // _beneficiary == advisorWallet
            totalAllocation = ADVISOR_ALLOCATION;
            releasedAmount = advisorTokensReleased;
            cliff = ADVISOR_CLIFF;
            vestingDuration = ADVISOR_VESTING_DURATION;
        }

        // If vesting hasn't started or we're before the cliff
        if (block.timestamp < vestingStartTime + cliff) {
            return 0;
        }

        // Calculate vested amount based on linear vesting
        uint256 vestedAmount;
        if (block.timestamp >= vestingStartTime + cliff + vestingDuration) {
            // If vesting period is complete, all tokens are vested
            vestedAmount = totalAllocation;
        } else {
            // Linear vesting calculation
            uint256 timeFromCliff = block.timestamp -
                (vestingStartTime + cliff);
            vestedAmount = (totalAllocation * timeFromCliff) / vestingDuration;
        }

        // Releasable is vested minus already released
        return
            vestedAmount > releasedAmount ? vestedAmount - releasedAmount : 0;
    }

    /**
     * @dev Release vested tokens for caller
     */
    function claimTokens() external nonReentrant {
        uint256 amount = calculateReleasableAmount(msg.sender);
        require(amount > 0, "No tokens available for release");

        if (msg.sender == teamWallet) {
            teamTokensReleased = teamTokensReleased + amount;
        } else if (msg.sender == advisorWallet) {
            advisorTokensReleased = advisorTokensReleased + amount;
        }

        binGoldToken.safeTransfer(msg.sender, amount);
        emit TokensReleased(msg.sender, amount);
    }

    /**
     * @dev Get vesting information for a beneficiary
     * @param _beneficiary Address of the beneficiary
     * @return totalAllocation Total allocation amount
     * @return releasedAmount Amount already released
     * @return releasableAmount Amount available for release
     * @return vestingStartDate Timestamp when vesting started
     * @return cliffEndDate Timestamp when cliff ends
     * @return vestingEndDate Timestamp when vesting ends
     */
    function getVestingInfo(
        address _beneficiary
    )
        external
        view
        returns (
            uint256 totalAllocation,
            uint256 releasedAmount,
            uint256 releasableAmount,
            uint256 vestingStartDate,
            uint256 cliffEndDate,
            uint256 vestingEndDate
        )
    {
        uint256 cliff;
        uint256 duration;

        if (_beneficiary == teamWallet) {
            totalAllocation = TEAM_ALLOCATION;
            releasedAmount = teamTokensReleased;
            cliff = TEAM_CLIFF;
            duration = TEAM_VESTING_DURATION;
        } else if (_beneficiary == advisorWallet) {
            totalAllocation = ADVISOR_ALLOCATION;
            releasedAmount = advisorTokensReleased;
            cliff = ADVISOR_CLIFF;
            duration = ADVISOR_VESTING_DURATION;
        } else {
            return (0, 0, 0, 0, 0, 0);
        }

        releasableAmount = calculateReleasableAmount(_beneficiary);
        vestingStartDate = vestingStartTime;
        cliffEndDate = vestingStartTime + cliff;
        vestingEndDate = vestingStartTime + cliff + duration;
    }
}
