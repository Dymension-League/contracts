// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Faucet Contract
 * @dev A simple faucet contract that allows authorized users to drip a certain amount of Ether to others
 */
contract Faucet {
    /// @notice Owner of the faucet
    address public owner;

    /// @notice Amount of Ether to drip per request
    uint256 public dripAmount;

    /// @notice Time period a user must wait between claims
    uint256 public cooldownPeriod;

    /// @notice Address of the authorized dripper
    address public authorizedDripper;

    /// @notice Tracks the last claimed timestamp for each user
    mapping(address => uint256) public lastClaimed;

    /// @notice Event emitted when a drip is claimed
    event DripClaimed(address indexed user, uint256 amount);

    /// @notice Event emitted when a drip is sent from one user to another
    event DripSent(address indexed from, address indexed to, uint256 amount);

    /// @notice Event emitted when ownership of the faucet is transferred
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Event emitted when the drip amount is changed
    event DripAmountChanged(uint256 newDripAmount);

    /// @notice Event emitted when the cooldown period is changed
    event CooldownPeriodChanged(uint256 newCooldownPeriod);

    /// @notice Event emitted when the authorized dripper is changed
    event AuthorizedDripperChanged(address newAuthorizedDripper);

    /// @notice Event emitted when the owner withdraws funds from the faucet
    event Withdrawal(address indexed to, uint256 amount);

    /// @notice Event emitted when a donation is made to the faucet
    event Donated(address indexed donator, uint256 amount);

    /// @notice Event emitted when the contract receives Ether directly
    event ReceivedEther(address indexed from, uint256 amount);

    /**
     * @dev Modifier to restrict functions to the contract owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    /**
     * @dev Modifier to check if a user can claim a drip based on the cooldown period
     */
    modifier canClaim(address claimer) {
        require(
            lastClaimed[claimer] == 0 || block.timestamp >= lastClaimed[claimer] + cooldownPeriod,
            "Cooldown period not reached"
        );
        _;
    }

    /**
     * @dev Modifier to restrict functions to the authorized dripper
     */
    modifier onlyAuthorizedDripper() {
        require(msg.sender == authorizedDripper, "Not authorized to send drips");
        _;
    }

    /**
     * @param _dripAmount Initial drip amount in ether
     * @param _cooldownPeriod Initial cooldown period in days
     * @param _authorizedDripper Address of the initial authorized dripper
     */
    constructor(uint256 _dripAmount, uint256 _cooldownPeriod, address _authorizedDripper) {
        owner = msg.sender;
        dripAmount = _dripAmount * 1 ether;
        cooldownPeriod = _cooldownPeriod * 1 days;
        authorizedDripper = _authorizedDripper;
    }

    /**
     * @notice Allows users to claim a drip of Ether
     * @dev Function will revert if the cooldown period has not been met or if the contract balance is insufficient
     */
    function claimDrip() external canClaim(msg.sender) {
        require(address(this).balance >= dripAmount, "Insufficient contract balance");

        lastClaimed[msg.sender] = block.timestamp;
        payable(msg.sender).transfer(dripAmount);

        emit DripClaimed(msg.sender, dripAmount);
    }

    /**
     * @notice Allows anyone to donate Ether to the faucet
     * @dev Function will revert if no Ether is sent
     */
    function donate() external payable {
        require(msg.value > 0, "Must send Ether to donate");
        emit Donated(msg.sender, msg.value);
    }

    /**
     * @notice Allows the authorized dripper to send a drip to another user
     * @param to The address to send the drip to
     * @dev Function will revert if the contract balance is insufficient
     */
    function sendDrip(address to) external onlyAuthorizedDripper canClaim(to) {
        require(address(this).balance >= dripAmount, "Insufficient contract balance");

        lastClaimed[to] = block.timestamp;
        payable(to).transfer(dripAmount);

        emit DripSent(msg.sender, to, dripAmount);
    }

    /**
     * @notice Allows the owner to withdraw the entire balance of the contract
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner).transfer(balance);

        emit Withdrawal(owner, balance);
    }

    /**
     * @notice Allows the owner to set a new drip amount
     * @param _dripAmount The new drip amount in ether
     */
    function setDripAmount(uint256 _dripAmount) external onlyOwner {
        dripAmount = _dripAmount * 1 ether;

        emit DripAmountChanged(_dripAmount);
    }

    /**
     * @notice Allows the owner to set a new cooldown period
     * @param _cooldownPeriod The new cooldown period in days
     */
    function setCooldownPeriod(uint256 _cooldownPeriod) external onlyOwner {
        cooldownPeriod = _cooldownPeriod * 1 days;

        emit CooldownPeriodChanged(_cooldownPeriod);
    }

    /**
     * @notice Allows the owner to change the authorized dripper
     * @param _authorizedDripper The address of the new authorized dripper
     */
    function setAuthorizedDripper(address _authorizedDripper) external onlyOwner {
        authorizedDripper = _authorizedDripper;

        emit AuthorizedDripperChanged(_authorizedDripper);
    }

    /**
     * @notice Allows the contract to receive Ether directly
     * @dev Emits a `ReceivedEther` event when Ether is received
     */
    receive() external payable {
        emit ReceivedEther(msg.sender, msg.value);
    }

    /**
     * @notice Allows the owner to transfer ownership of the contract
     * @param newOwner The address of the new owner
     * @dev Function will revert if the new owner address is zero
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
