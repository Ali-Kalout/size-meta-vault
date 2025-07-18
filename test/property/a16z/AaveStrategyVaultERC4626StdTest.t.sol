// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ERC4626Test, IMockERC20} from "@a16z/erc4626-tests/ERC4626.test.sol";
import {BaseTest} from "@test/BaseTest.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {WadRayMath} from "@aave/contracts/protocol/libraries/math/WadRayMath.sol";

contract AaveStrategyVaultERC4626StdTest is ERC4626Test, BaseTest {
    function setUp() public override(ERC4626Test, BaseTest) {
        super.setUp();

        vm.prank(admin);
        Ownable(address(erc20Asset)).transferOwnership(address(this));

        _underlying_ = address(erc20Asset);
        _vault_ = address(aaveStrategyVault);
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = true;
    }

    function setUpYield(ERC4626Test.Init memory init) public override {
        uint256 balance = erc20Asset.balanceOf(address(aToken));
        if (init.yield >= 0) {
            // gain
            vm.assume(init.yield < int256(uint256(type(uint128).max)));
            init.yield = bound(init.yield, 0, int256(balance / 100));
            uint256 gain = uint256(init.yield);
            IMockERC20(_underlying_).mint(address(aToken), gain);
            vm.prank(admin);
            pool.setLiquidityIndex(address(erc20Asset), (balance + gain) * WadRayMath.RAY / balance);
        } else {
            // loss
            vm.assume(init.yield > type(int128).min);
            uint256 loss = uint256(-1 * init.yield);
            vm.assume(loss < balance);
            IMockERC20(_underlying_).burn(address(aToken), loss);
        }
    }

    function test_AaveStrategyVaultERC4626StdTest_RT_withdraw_mint_01() public {
        Init memory init = Init({
            user: [
                0x000000000000000000000000000000000000369F,
                0x000000000000000000000000000000000000097B,
                0x0000000000000000000000000000000000000974,
                0x00000000000000000000000000000000bf92857D
            ],
            share: [uint256(3212384070), uint256(4897), uint256(579), uint256(11295)],
            asset: [uint256(7109), uint256(6682), uint256(1168), uint256(4352)],
            yield: int256(15660)
        });
        test_RT_withdraw_mint(init, 3118930328);
    }

    function test_RT_redeem_deposit(Init memory init, uint256 shares) public override {
        // ignore
    }

    function test_RT_redeem_mint(Init memory init, uint256 shares) public override {
        // ignore
    }

    function test_RT_withdraw_mint(Init memory init, uint256 assets) public override {
        // ignore
    }
}
