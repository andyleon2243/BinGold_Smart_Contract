/**
 *Submitted for verification at BscScan.com on 2022-12-14
 */

// SPDX-License-Identifier: NONE

pragma solidity ^0.8.11;

import "./BasicMetaTransaction.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IBinGold.sol";

/**
 * @title BinGoldImplementation
 * @dev this contract is a Pausable ERC20 token with Burn and Mint
 * controlled by a central SupplyController. By implementing BinGoldImplementation
 * this contract also includes external methods for setting
 * a new implementation contract for the Proxy.
 * NOTE: The storage defined here will actually be held in the Proxy
 * contract and all calls to this contract should be made through
 * the proxy, including admin actions done as owner or supplyController.
 * Any call to transferransaction against this contract should fail
 * with insufficient funds since no tokens will be issued there.
 */
contract BinGoldToken is BasicMetaTransaction, Initializable, IBinGold {
    /**
     * DATA
     */

    // Maximum supply constant (2.5 million tokens with 6 decimals)
    uint256 public constant MAX_SUPPLY = 2_500_000 * 10 ** decimals;

    // Track total minted amount
    uint256 public totalMinted;

    // ERC20 BASIC DATA
    mapping(address => uint256) internal balances;
    uint256 internal totalSupply_;
    string public constant name = "BinGold Token"; 
    string public constant symbol = "BIGOD"; 
    uint8 public constant decimals = 6;
    // ERC20 DATA
    mapping(address => mapping(address => uint256)) internal allowed;

    // OWNER DATA
    address public owner;
    address public proposedOwner;

    // PAUSABILITY DATA
    bool public paused;

    // ASSET PROTECTION DATA
    address public assetProtectionRole;
    mapping(address => bool) internal frozen;

    // SUPPLY CONTROL DATA
    address public supplyController;

    // DELEGATED TRANSFER DATA
    address public betaDelegateWhitelister;
    mapping(address => bool) internal betaDelegateWhitelist;
    mapping(address => uint256) internal nextSeqs;
    // EIP191 header for EIP712 prefix
    string internal constant EIP191_HEADER = "\x19\x01";
    // Hash of the EIP712 Domain Separator Schema
    bytes32 internal constant EIP712_DOMAIN_SEPARATOR_SCHEMA_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
    bytes32 internal constant EIP712_DELEGATED_TRANSFER_SCHEMA_HASH =
        keccak256(
            "BetaDelegatedTransfer(address to,uint256 value,uint256 serviceFee,uint256 seq,uint256 deadline)"
        );
    // Hash of the EIP712 Domain Separator data
    // solhint-disable-next-line var-name-mixedcase
    bytes32 public EIP712_DOMAIN_HASH;

    // FEE CONTROLLER DATA
    // fee decimals is only set for informational purposes.
    // 1 feeRate = .000001 oz of gold or ( 10 ** -6 )
    uint8 public constant feeDecimals = 6;

    // feeRate is measured in 100th of a basis point (parts per 1,000,000)
    // ex: a fee rate of 200= 200/10**-6 = 0.0002 =  0.02% of an oz of gold
    //implies that if you have 1 ounce of gold, the fee corresponds to 0.02% of the value of that gold.
    // 10 lakh points = 100% || 1 lakh points = 10% || 10,000 points = 1%  || 1000 points = 0.1% || 100 points = 0.01%
    uint256 public constant feeParts = 1000000;
    uint256 public feeRate;
    address public feeController;
    address public feeRecipient;

    /**
     * EVENTS
     */

    // OWNABLE EVENTS
    event OwnershipTransferProposed(
        address indexed currentOwner,
        address indexed proposedOwner
    );
    event OwnershipTransferDisregarded(address indexed oldProposedOwner);
    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );

    // PAUSABLE EVENTS
    event Pause();
    event Unpause();

    // ASSET PROTECTION EVENTS
    event AddressFrozen(address indexed addr);
    event AddressUnfrozen(address indexed addr);
    event FrozenAddressWiped(address indexed addr);
    event AssetProtectionRoleSet(
        address indexed oldAssetProtectionRole,
        address indexed newAssetProtectionRole
    );

    // SUPPLY CONTROL EVENTS
    event SupplyIncreased(address indexed to, uint256 value);
    event SupplyDecreased(address indexed from, uint256 value);
    event SupplyControllerSet(
        address indexed oldSupplyController,
        address indexed newSupplyController
    );

    // DELEGATED TRANSFER EVENTS
    event BetaDelegatedTransfer(
        address indexed from,
        address indexed to,
        uint256 value,
        uint256 seq,
        uint256 serviceFee
    );
    event BetaDelegateWhitelisterSet(
        address indexed oldWhitelister,
        address indexed newWhitelister
    );
    event BetaDelegateWhitelisted(address indexed newDelegate);
    event BetaDelegateUnwhitelisted(address indexed oldDelegate);

    // FEE CONTROLLER EVENTS
    event FeeTransfer(address indexed from, address indexed to, uint256 value);
    event FeeCollected(address indexed from, address indexed to, uint256 value);
    event FeeRateSet(uint256 indexed oldFeeRate, uint256 indexed newFeeRate);
    event FeeControllerSet(
        address indexed oldFeeController,
        address indexed newFeeController
    );
    event FeeRecipientSet(
        address indexed oldFeeRecipient,
        address indexed newFeeRecipient
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * FUNCTIONALITY
     */

    // INITIALIZATION FUNCTIONALITY

    /**
     * @dev sets 0 initial tokens, the owner, the supplyController,
     * the fee controller and fee recipient.
     * this serves as the constructor for the proxy but compiles to the
     * memory model of the Implementation contract.
     */
    function initialize(address _owner) public initializer {
        require(_owner != address(0), "Owner cannot be zero address");
        owner = _owner;
        proposedOwner = address(0);
        assetProtectionRole = address(0);
        totalSupply_ = 0;
        supplyController = _owner;
        feeRate = 0;
        feeController = _owner;
        feeRecipient = _owner;
        initializeDomainSeparator();
        paused = false;
    }

    /**
     * The constructor is used here to ensure that the implementation
     * contract is initialized. An uncontrolled implementation
     * contract might lead to misleading state
     * for users who accidentally interact with it.
     */

    /**
     * @dev To be called when upgrading the contract using upgradeAndCall to add delegated transfers
     */
    function initializeDomainSeparator() internal {
        // hash the name context with the contract address and current chain ID
        EIP712_DOMAIN_HASH = keccak256(
            abi.encode(
                EIP712_DOMAIN_SEPARATOR_SCHEMA_HASH,
                keccak256(bytes(name)),
                keccak256(bytes("1")), // version
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @dev Returns the current domain separator hash with the current chain ID
     * This ensures protection against cross-chain replay attacks even after hard forks
     */
    function _getCurrentDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    EIP712_DOMAIN_SEPARATOR_SCHEMA_HASH,
                    keccak256(bytes(name)),
                    keccak256(bytes("1")), // version
                    block.chainid,
                    address(this)
                )
            );
    }

    // ERC20 BASIC FUNCTIONALITY

    /**
     * @dev Total number of tokens in existence
     */
    function totalSupply() public view returns (uint256) {
        return totalSupply_;
    }

    /**
     * @dev Transfer token to a specified address from msg.sender
     * Transfer additionally sends the fee to the fee controller
     * @param _to The address to transfer to.
     * @param _value The amount to be transferred.
     */
    function transfer(
        address _to,
        uint256 _value
    ) public whenNotPaused returns (bool) {
        require(_to != address(0), "cannot transfer to address zero");
        require(!frozen[_to] && !frozen[_msgSender()], "address frozen");
        require(_value <= balances[_msgSender()], "insufficient funds");

        _transfer(_msgSender(), _to, _value);
        return true;
    }

    /**
     * @dev Gets the balance of the specified address.
     * @param _addr The address to query the the balance of.
     * @return An uint256 representing the amount owned by the passed address.
     */
    function balanceOf(address _addr) public view returns (uint256) {
        return balances[_addr];
    }

    // ERC20 FUNCTIONALITY

    /**
     * @dev Transfer tokens from one address to another
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public whenNotPaused returns (bool) {
        require(_to != address(0), "cannot transfer to address zero");
        require(
            !frozen[_to] && !frozen[_from] && !frozen[_msgSender()],
            "address frozen"
        );
        require(_value <= balances[_from], "insufficient funds");
        require(
            _value <= allowed[_from][_msgSender()],
            "insufficient allowance"
        );

        allowed[_from][_msgSender()] = allowed[_from][_msgSender()] - _value;
        _transfer(_from, _to, _value);

        return true;
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of _msgSender().
     * Beware that changing an allowance with this method brings the risk that someone may use both the old
     * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
     * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(
        address _spender,
        uint256 _value
    ) public whenNotPaused returns (bool) {
        require(!frozen[_spender] && !frozen[_msgSender()], "address frozen");
        allowed[_msgSender()][_spender] = _value;
        emit Approval(_msgSender(), _spender, _value);
        return true;
    }

    /**
     * @dev Function to check the amount of tokens that an owner allowed to a spender.
     * @param _owner address The address which owns the funds.
     * @param _spender address The address which will spend the funds.
     * @return A uint256 specifying the amount of tokens still available for the spender.
     */
    function allowance(
        address _owner,
        address _spender
    ) public view returns (uint256) {
        return allowed[_owner][_spender];
    }

    function _transfer(
        address _from,
        address _to,
        uint256 _value
    ) internal returns (uint256) {
        uint256 _fee = getFeeFor(_value);
        uint256 _principle = _value - _fee;
        balances[_from] = balances[_from] - _value;
        balances[_to] = balances[_to] + _principle;
        emit Transfer(_from, _to, _principle);
        emit FeeTransfer(_from, feeRecipient, _fee);
        if (_fee > 0) {
            balances[feeRecipient] = balances[feeRecipient] + _fee;
            emit FeeCollected(_from, feeRecipient, _fee);
        }

        return _principle;
    }

    // OWNER FUNCTIONALITY

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_msgSender() == owner, "onlyOwner");
        _;
    }

    /**
     * @dev Allows the current owner to begin transferring control of the contract to a proposedOwner
     * @param _proposedOwner The address to transfer ownership to.
     */
    function proposeOwner(address _proposedOwner) public onlyOwner {
        require(
            _proposedOwner != address(0),
            "cannot transfer ownership to address zero"
        );
        require(_msgSender() != _proposedOwner, "caller already is owner");
        proposedOwner = _proposedOwner;
        emit OwnershipTransferProposed(owner, proposedOwner);
    }

    /**
     * @dev Allows the current owner or proposed owner to cancel transferring control of the contract to a proposedOwner
     */
    function disregardProposeOwner() public {
        require(
            _msgSender() == proposedOwner || _msgSender() == owner,
            "only proposedOwner or owner"
        );
        require(
            proposedOwner != address(0),
            "can only disregard a proposed owner that was previously set"
        );
        address _oldProposedOwner = proposedOwner;
        proposedOwner = address(0);
        emit OwnershipTransferDisregarded(_oldProposedOwner);
    }

    /**
     * @dev Allows the proposed owner to complete transferring control of the contract to the proposedOwner.
     */
    function claimOwnership() public {
        require(_msgSender() == proposedOwner, "onlyProposedOwner");
        address _oldOwner = owner;
        owner = proposedOwner;
        proposedOwner = address(0);
        emit OwnershipTransferred(_oldOwner, owner);
    }

    /**
     * @dev Reclaim all BLDGST at the contract address.
     * This sends the BLDGST tokens that this contract add holding to the owner.
     * Note: this is not affected by freeze constraints.
     */
    function reclaimCoin() external onlyOwner {
        uint256 _balance = balances[address(this)];
        balances[address(this)] = 0;
        balances[owner] = balances[owner] + _balance;
        emit Transfer(address(this), owner, _balance);
    }

    // PAUSABILITY FUNCTIONALITY

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        require(!paused, "whenNotPaused");
        _;
    }

    /**
     * @dev called by the owner to pause, triggers stopped state
     */
    function pause() public onlyOwner {
        require(!paused, "already paused");
        paused = true;
        emit Pause();
    }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */
    function unpause() public onlyOwner {
        require(paused, "already unpaused");
        paused = false;
        emit Unpause();
    }

    // ASSET PROTECTION FUNCTIONALITY

    /**
     * @dev Sets a new asset protection role address.
     * @param _newAssetProtectionRole The new address allowed to freeze/unfreeze addresses and seize their tokens.
     */
    function setAssetProtectionRole(address _newAssetProtectionRole) public {
        require(
            _newAssetProtectionRole != address(0),
            "Cannot set role to address zero"
        );
        require(
            _msgSender() == assetProtectionRole || _msgSender() == owner,
            "only assetProtectionRole or Owner"
        );
        emit AssetProtectionRoleSet(
            assetProtectionRole,
            _newAssetProtectionRole
        );
        assetProtectionRole = _newAssetProtectionRole;
    }

    modifier onlyAssetProtectionRole() {
        require(_msgSender() == assetProtectionRole, "onlyAssetProtectionRole");
        _;
    }

    /**
     * @dev Freezes an address balance from being transferred.
     * @param _addr The new address to freeze.
     */
    function freeze(address _addr) public onlyAssetProtectionRole {
        require(!frozen[_addr], "address already frozen");
        frozen[_addr] = true;
        emit AddressFrozen(_addr);
    }

    /**
     * @dev Unfreezes an address balance allowing transfer.
     * @param _addr The new address to unfreeze.
     */
    function unfreeze(address _addr) public onlyAssetProtectionRole {
        require(frozen[_addr], "address already unfrozen");
        frozen[_addr] = false;
        emit AddressUnfrozen(_addr);
    }

    /**
     * @dev Wipes the balance of a frozen address, burning the tokens
     * and setting the approval to zero.
     * @param _addr The new frozen address to wipe.
     */
    function wipeFrozenAddress(address _addr) public onlyAssetProtectionRole {
        require(frozen[_addr], "address is not frozen");
        uint256 _balance = balances[_addr];
        balances[_addr] = 0;
        totalSupply_ = totalSupply_ - _balance;
        emit FrozenAddressWiped(_addr);
        emit SupplyDecreased(_addr, _balance);
        emit Transfer(_addr, address(0), _balance);
    }

    /**
     * @dev Gets whether the address is currently frozen.
     * @param _addr The address to check if frozen.
     * @return A bool representing whether the given address is frozen.
     */
    function isFrozen(address _addr) public view returns (bool) {
        return frozen[_addr];
    }

    // SUPPLY CONTROL FUNCTIONALITY

    /**
     * @dev Sets a new supply controller address.
     * @param _newSupplyController The address allowed to burn/mint tokens to control supply.
     */
    function setSupplyController(address _newSupplyController) public {
        require(
            _msgSender() == supplyController || _msgSender() == owner,
            "only SupplyController or Owner"
        );
        require(
            _newSupplyController != address(0),
            "cannot set supply controller to address zero"
        );
        emit SupplyControllerSet(supplyController, _newSupplyController);
        supplyController = _newSupplyController;
    }

    modifier onlySupplyController() {
        require(_msgSender() == supplyController, "onlySupplyController");
        _;
    }

    /**
     * @dev Increases the total supply by minting the specified number of tokens to the supply controller account.
     * @param _value The number of tokens to add.
     * @return  success A boolean that indicates if the operation was successful.
     */
    function increaseSupply(
        uint256 _value
    ) public onlySupplyController returns (bool success) {
        require(totalSupply_ + _value <= MAX_SUPPLY, "MAX Supply exceeded");

        totalSupply_ = totalSupply_ + _value;
        totalMinted = totalMinted + _value;
        balances[supplyController] = balances[supplyController] + _value;

        emit SupplyIncreased(supplyController, _value);
        emit Transfer(address(0), supplyController, _value);
        return true;
    }

    /**
     * @dev Decreases the total supply by burning the specified number of tokens from the supply controller account.
     * @param _value The number of tokens to remove.
     * @return  success A boolean that indicates if the operation was successful.
     */
    function decreaseSupply(
        uint256 _value
    ) public onlySupplyController returns (bool success) {
        require(_value <= balances[supplyController], "not enough supply");
        balances[supplyController] = balances[supplyController] - _value;
        totalSupply_ = totalSupply_ - _value;
        emit SupplyDecreased(supplyController, _value);
        emit Transfer(supplyController, address(0), _value);
        return true;
    }

    // DELEGATED TRANSFER FUNCTIONALITY

    /**
     * @dev returns the next seq for a target address.
     * The transactor must submit nextSeqOf(transactor) in the next transaction for it to be valid.
     * Note: that the seq context is specific to this smart contract.
     * @param target The target address.
     * @return the seq.
     */
    //
    function nextSeqOf(address target) public view returns (uint256) {
        return nextSeqs[target];
    }

    /**
     * @dev Performs a transfer on behalf of the from address, identified by its signature on the delegatedTransfer msg.
     * Splits a signature byte array into r,s,v for convenience.
     * @param sig the signature of the delgatedTransfer msg.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @param serviceFee an optional ERC20 service fee paid to the executor of betaDelegatedTransfer by the from address.
     * @param seq a sequencing number included by the from address specific to this contract to protect from replays.
     * @param deadline a block number after which the pre-signed transaction has expired.
     */
    function betaDelegatedTransfer(
        bytes memory sig,
        address to,
        uint256 value,
        uint256 serviceFee,
        uint256 seq,
        uint256 deadline
    ) public {
        require(sig.length == 65, "signature should have length 65");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        _betaDelegatedTransfer(r, s, v, to, value, serviceFee, seq, deadline);
    }

    /**
     * @dev Performs a transfer on behalf of the from address, identified by its signature on the betaDelegatedTransfer msg.
     * Note: both the delegate and transactor sign in the service fees. The transactor, however,
     * has no control over the gas price, and therefore no control over the transaction time.
     * Beta prefix chosen to avoid a name clash with an emerging standard in ERC865 or elsewhere.
     * Internal to the contract - see betaDelegatedTransfer and betaDelegatedTransferBatch.
     * Security: Uses EIP712 with current chain ID to prevent cross-chain replay attacks.
     * @param r the r signature of the delgatedTransfer msg.
     * @param s the s signature of the delgatedTransfer msg.
     * @param v the v signature of the delgatedTransfer msg.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @param serviceFee an optional ERC20 service fee paid to the delegate of betaDelegatedTransfer by the from address.
     * @param seq a sequencing number included by the from address specific to this contract to protect from replays.
     * @param deadline a block number after which the pre-signed transaction has expired.
     * @return A boolean that indicates if the operation was successful.
     */
    function _betaDelegatedTransfer(
        bytes32 r,
        bytes32 s,
        uint8 v,
        address to,
        uint256 value,
        uint256 serviceFee,
        uint256 seq,
        uint256 deadline
    ) internal whenNotPaused returns (bool) {
        require(
            betaDelegateWhitelist[_msgSender()],
            "Beta feature only accepts whitelisted delegates"
        );
        require(
            value > 0 || serviceFee > 0,
            "cannot transfer zero tokens with zero service fee"
        );
        require(block.number <= deadline, "transaction expired");
        // prevent sig malleability from ecrecover()
        require(
            uint256(s) <=
                0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
            "signature incorrect"
        );
        require(v == 27 || v == 28, "signature incorrect");

        // EIP712 scheme: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md
        // Use current domain separator to protect against cross-chain replay attacks
        bytes32 domainSeparator = _getCurrentDomainSeparator();
        bytes32 structHash = keccak256(
            abi.encode(
                EIP712_DELEGATED_TRANSFER_SCHEMA_HASH,
                to,
                value,
                serviceFee,
                seq,
                deadline
            )
        );
        bytes32 hash = keccak256(
            abi.encodePacked(EIP191_HEADER, domainSeparator, structHash)
        );
        address _from = ecrecover(hash, v, r, s);

        require(
            _from != address(0),
            "error determining from address from signature"
        );
        require(to != address(0), "cannot use address zero");
        require(
            !frozen[to] && !frozen[_from] && !frozen[_msgSender()],
            "address frozen"
        );
        require(
            value + serviceFee <= balances[_from],
            "insufficient funds or bad signature"
        );
        require(nextSeqs[_from] == seq, "incorrect seq");

        nextSeqs[_from] = nextSeqs[_from] + 1;

        uint256 _principle = _transfer(_from, to, value);

        if (serviceFee != 0) {
            balances[_from] = balances[_from] - (serviceFee);
            balances[_msgSender()] = balances[_msgSender()] + serviceFee;
            emit Transfer(_from, _msgSender(), serviceFee);
        }

        emit BetaDelegatedTransfer(_from, to, _principle, seq, serviceFee);
        return true;
    }

    /**
     * @dev Performs an atomic batch of transfers on behalf of the from addresses, identified by their signatures.
     * Lack of nested array support in arguments requires all arguments to be passed as equal size arrays where
     * delegated transfer number i is the combination of all arguments at index i
     * @param r the r signatures of the delgatedTransfer msg.
     * @param s the s signatures of the delgatedTransfer msg.
     * @param v the v signatures of the delgatedTransfer msg.
     * @param to The addresses to transfer to.
     * @param value The amounts to be transferred.
     * @param serviceFee optional ERC20 service fees paid to the delegate of betaDelegatedTransfer by the from address.
     * @param seq sequencing numbers included by the from address specific to this contract to protect from replays.
     * @param deadline block numbers after which the pre-signed transactions have expired.
     * @return A boolean that indicates if the operation was successful.
     */
    function betaDelegatedTransferBatch(
        bytes32[] calldata r,
        bytes32[] calldata s,
        uint8[] calldata v,
        address[] calldata to,
        uint256[] memory value,
        uint256[] memory serviceFee,
        uint256[] memory seq,
        uint256[] memory deadline
    ) public returns (bool) {
        require(
            r.length == s.length &&
                r.length == v.length &&
                r.length == to.length &&
                r.length == value.length,
            "length mismatch"
        );
        require(
            r.length == serviceFee.length &&
                r.length == seq.length &&
                r.length == deadline.length,
            "length mismatch"
        );

        for (uint i = 0; i < r.length; i++) {
            _betaDelegatedTransfer(
                r[i],
                s[i],
                v[i],
                to[i],
                value[i],
                serviceFee[i],
                seq[i],
                deadline[i]
            );
        }
        return true;
    }

    /**
     * @dev Gets whether the address is currently whitelisted for betaDelegateTransfer.
     * @param _addr The address to check if whitelisted.
     * @return A bool representing whether the given address is whitelisted.
     */
    function isWhitelistedBetaDelegate(
        address _addr
    ) public view returns (bool) {
        return betaDelegateWhitelist[_addr];
    }

    /**
     * @dev Sets a new betaDelegate whitelister.
     * @param _newWhitelister The address allowed to whitelist betaDelegates.
     */
    function setBetaDelegateWhitelister(address _newWhitelister) public {
        require(
            _newWhitelister != address(0),
            "Cannot set whitelister to address zero"
        );
        require(
            _msgSender() == betaDelegateWhitelister || _msgSender() == owner,
            "only Whitelister or Owner"
        );
        betaDelegateWhitelister = _newWhitelister;
        emit BetaDelegateWhitelisterSet(
            betaDelegateWhitelister,
            _newWhitelister
        );
    }

    modifier onlyBetaDelegateWhitelister() {
        require(
            _msgSender() == betaDelegateWhitelister,
            "onlyBetaDelegateWhitelister"
        );
        _;
    }

    /**
     * @dev Whitelists an address to allow calling BetaDelegatedTransfer.
     * @param _addr The new address to whitelist.
     */
    function whitelistBetaDelegate(
        address _addr
    ) public onlyBetaDelegateWhitelister {
        require(!betaDelegateWhitelist[_addr], "delegate already whitelisted");
        betaDelegateWhitelist[_addr] = true;
        emit BetaDelegateWhitelisted(_addr);
    }

    /**
     * @dev Unwhitelists an address to disallow calling BetaDelegatedTransfer.
     * @param _addr The new address to whitelist.
     */
    function unwhitelistBetaDelegate(
        address _addr
    ) public onlyBetaDelegateWhitelister {
        require(betaDelegateWhitelist[_addr], "delegate not whitelisted");
        betaDelegateWhitelist[_addr] = false;
        emit BetaDelegateUnwhitelisted(_addr);
    }

    // FEE CONTROLLER FUNCTIONALITY

    /**
     * @dev Sets a new fee controller address.
     * @param _newFeeController The address allowed to set the fee rate and the fee recipient.
     */
    function setFeeController(address _newFeeController) public {
        require(
            _msgSender() == feeController || _msgSender() == owner,
            "only FeeController or Owner"
        );
        require(
            _newFeeController != address(0),
            "cannot set fee controller to address zero"
        );
        address _oldFeeController = feeController;
        feeController = _newFeeController;
        emit FeeControllerSet(_oldFeeController, feeController);
    }

    modifier onlyFeeController() {
        require(_msgSender() == feeController, "only FeeController");
        _;
    }

    /**
     * @dev Sets a new fee recipient address.
     * @param _newFeeRecipient The address allowed to collect transfer fees for transfers.
     */
    function setFeeRecipient(
        address _newFeeRecipient
    ) public onlyFeeController {
        require(
            _newFeeRecipient != address(0),
            "cannot set fee recipient to address zero"
        );
        address _oldFeeRecipient = feeRecipient;
        feeRecipient = _newFeeRecipient;
        emit FeeRecipientSet(_oldFeeRecipient, feeRecipient);
    }

    /**
     * @dev Sets a new fee rate.
     * @param _newFeeRate The new fee rate to collect as transfer fees for transfers.
     */
    function setFeeRate(uint256 _newFeeRate) public onlyFeeController {
        require(_newFeeRate < feeParts, "cannot set fee rate above 100%");
        uint256 _oldFeeRate = feeRate;
        feeRate = _newFeeRate;
        emit FeeRateSet(_oldFeeRate, feeRate);
    }

    /**
     * @dev Gets a fee for a given value
     * ex: given feeRate = 200 and feeParts = 1,000,000 then getFeeFor(10000) = 2
     * @param _value The amount to get the fee for.
     */
    function getFeeFor(uint256 _value) public view returns (uint256) {
        if (feeRate == 0) {
            return 0;
        }

        return (_value * (feeRate)) / feeParts;
    }

    function _msgSender()
        internal
        view
        virtual
        override
        returns (address sender)
    {
        if (msg.sender == address(this)) {
            bytes memory array = msg.data;
            uint256 index = msg.data.length;
            assembly {
                // Load the 32 bytes word from memory with the address on the lower 20 bytes, and mask those.
                sender := and(
                    mload(add(array, index)),
                    0xffffffffffffffffffffffffffffffffffffffff
                )
            }
        } else {
            return msg.sender;
        }
    }
}
