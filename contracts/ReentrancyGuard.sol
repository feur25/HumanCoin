pragma solidity ^0.8.2;

contract ReentrancyGuard {
    bool private _notEntered;

    constructor () {
        _notEntered = true;
    }

    modifier noReentrancy() {
        require(_notEntered, "Reentrant call");
        _;
        _notEntered = true;
    }
}