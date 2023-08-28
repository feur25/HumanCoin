pragma solidity >=0.7.0 <0.9.0;

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