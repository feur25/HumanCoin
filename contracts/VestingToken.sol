pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./Token.sol";

contract VestingToken is Ownable, ERC20 {
    using SafeMath for uint256;

    struct VestingSchedule {
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 totalAmount;
        uint256 withdrawnAmount;
    }

    mapping(address => VestingSchedule[]) public vestingSchedules;

    constructor(uint256 initialSupply) ERC20("Vesting Token", "VTOKEN") {
        _mint(msg.sender, initialSupply * (10**decimals()));
    }

    function createVestingSchedule(address beneficiary, uint256 startTimestamp, uint256 endTimestamp, uint256 totalAmount) public onlyOwner {
        require(endTimestamp > startTimestamp, "Invalid schedule duration");
        require(totalAmount > 0, "Invalid amount");

        VestingSchedule memory schedule = VestingSchedule({
            startTimestamp: startTimestamp,
            endTimestamp: endTimestamp,
            totalAmount: totalAmount,
            withdrawnAmount: 0
        });

        vestingSchedules[beneficiary].push(schedule);
    }

    function withdrawVestedTokens() public {
        uint256 totalVestedTokens;
        VestingSchedule[] storage schedules = vestingSchedules[msg.sender];

        for (uint256 i = 0; i < schedules.length; i++) {
            VestingSchedule storage schedule = schedules[i];

            if (block.timestamp >= schedule.startTimestamp && block.timestamp <= schedule.endTimestamp) {
                uint256 elapsedTime = block.timestamp - schedule.startTimestamp;
                uint256 vestingDuration = schedule.endTimestamp - schedule.startTimestamp;

                uint256 vestedAmount = schedule.totalAmount.mul(elapsedTime).div(vestingDuration).sub(schedule.withdrawnAmount);

                if (vestedAmount > 0) {
                    _transfer(address(this), msg.sender, vestedAmount);
                    schedule.withdrawnAmount = schedule.withdrawnAmount.add(vestedAmount);
                    totalVestedTokens = totalVestedTokens.add(vestedAmount);
                }
            }
        }

        require(totalVestedTokens > 0, "No vested tokens available");
    }
}
