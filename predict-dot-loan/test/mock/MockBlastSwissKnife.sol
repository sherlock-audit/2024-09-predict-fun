// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {YieldMode, GasMode} from "../../contracts/interfaces/IBlast.sol";

/**
 * @title MockBlastSwissKnife
 * @notice This contract is a combination of MockBlastYield and MockBlastPoints to avoid the EVM revert error in the invariant test.
 */
contract MockBlastSwissKnife {
    struct Config {
        YieldMode yieldMode;
        GasMode gasMode;
        address governor;
    }

    mapping(address _contract => Config) public config;
    mapping(address _contract => address operator) public contractOperators;

    function configure(YieldMode _yield, GasMode _gasMode, address _governor) external {
        config[msg.sender] = Config(_yield, _gasMode, _governor);
    }

    function configurePointsOperator(address operator) external {
        contractOperators[msg.sender] = operator;
    }
}
