// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseTest} from "@test/BaseTest.t.sol";
import {AaveStrategyVault} from "@src/strategies/AaveStrategyVault.sol";
import {Auth} from "@src/Auth.sol";
import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IAToken} from "@aave/contracts/interfaces/IAToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {BaseVault} from "@src/BaseVault.sol";
import {DataTypes} from "@aave/contracts/protocol/libraries/types/DataTypes.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AaveStrategyVaultTest is BaseTest, Initializable {
    uint256 initialBalance;
    uint256 initialTotalAssets;

    function setUp() public override {
        super.setUp();
        initialTotalAssets = aaveStrategyVault.totalAssets();
        initialBalance = erc20Asset.balanceOf(address(aToken));
    }

    function test_AaveStrategyVault_initialize_invalid_asset() public {
        vm.store(address(aaveStrategyVault), _initializableStorageSlot(), bytes32(uint256(0)));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(BaseVault.InvalidAsset.selector, address(weth)));
        aaveStrategyVault.initialize(auth, IERC20(address(weth)), "VAULT", "VAULT", FIRST_DEPOSIT_AMOUNT, pool);
    }

    function test_AaveStrategyVault_transferAssets() public {
        uint256 amount = 100e6;
        _mint(erc20Asset, alice, amount);
        _approve(alice, erc20Asset, address(aaveStrategyVault), amount);
        vm.prank(alice);
        aaveStrategyVault.deposit(amount, alice);

        uint256 assetsAaveStrategyBefore = aaveStrategyVault.totalAssets();
        uint256 assetsCashStrategyBefore = cashStrategyVault.totalAssets();
        uint256 deadAssetsAaveStrategyVaultBefore = aaveStrategyVault.deadAssets();
        uint256 rebalanceAmount = assetsAaveStrategyBefore - deadAssetsAaveStrategyVaultBefore;

        assertEq(amount, rebalanceAmount);

        vm.prank(strategist);
        sizeMetaVault.rebalance(aaveStrategyVault, cashStrategyVault, rebalanceAmount, 0);

        uint256 assetsAaveStrategyAfter = aaveStrategyVault.totalAssets();
        uint256 assetsCashStrategyAfter = cashStrategyVault.totalAssets();
        uint256 deadAssetsAaveStrategyVaultAfter = aaveStrategyVault.deadAssets();

        assertEq(assetsAaveStrategyAfter, deadAssetsAaveStrategyVaultBefore);
        assertEq(assetsCashStrategyAfter, assetsCashStrategyBefore + rebalanceAmount);
        assertEq(deadAssetsAaveStrategyVaultBefore, deadAssetsAaveStrategyVaultAfter);
    }

    function test_AaveStrategyVault_skim() public {
        uint256 amount = 100e6;
        _mint(erc20Asset, alice, amount);
        _approve(alice, erc20Asset, address(cashStrategyVault), amount);
        vm.prank(alice);
        cashStrategyVault.deposit(amount, alice);

        address aTokenAddress =
            address(IAToken(aaveStrategyVault.pool().getReserveData(address(erc20Asset)).aTokenAddress));

        uint256 assetsCashStrategyVaultBeforeRebalance = erc20Asset.balanceOf(address(cashStrategyVault));
        uint256 assetsATokenBeforeRebalance = erc20Asset.balanceOf(aTokenAddress);

        vm.prank(strategist);
        sizeMetaVault.rebalance(cashStrategyVault, aaveStrategyVault, amount, 0);

        uint256 assetsATokenAfter = erc20Asset.balanceOf(aTokenAddress);
        uint256 assetsAaveStrategyVaultAfterReblance = erc20Asset.balanceOf(address(aaveStrategyVault));
        uint256 assetsCashStrategyVaultAfterRebalance = erc20Asset.balanceOf(address(cashStrategyVault));

        assertEq(assetsATokenAfter, assetsATokenBeforeRebalance + amount);
        assertEq(assetsAaveStrategyVaultAfterReblance, 0);
        assertEq(assetsCashStrategyVaultAfterRebalance, assetsCashStrategyVaultBeforeRebalance - amount);
    }

    function test_AaveStrategyVault_deposit_balanceOf_totalAssets() public {
        uint256 amount = 100e6;
        _mint(erc20Asset, alice, amount);
        _approve(alice, erc20Asset, address(aaveStrategyVault), amount);
        vm.prank(alice);
        aaveStrategyVault.deposit(amount, alice);
        assertEq(aaveStrategyVault.balanceOf(alice), amount);
        assertEq(aaveStrategyVault.totalAssets(), initialTotalAssets + amount);
        assertEq(erc20Asset.balanceOf(address(aToken)), initialBalance + amount);
        assertEq(erc20Asset.balanceOf(alice), 0);
    }

    function test_AaveStrategyVault_deposit_withdraw() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(aaveStrategyVault), depositAmount);
        vm.prank(alice);
        aaveStrategyVault.deposit(depositAmount, alice);
        assertEq(aaveStrategyVault.balanceOf(alice), depositAmount);
        assertEq(aaveStrategyVault.totalAssets(), initialTotalAssets + depositAmount);
        assertEq(erc20Asset.balanceOf(address(aToken)), initialBalance + depositAmount);
        assertEq(erc20Asset.balanceOf(alice), 0);

        uint256 withdrawAmount = 30e6;
        vm.prank(alice);
        aaveStrategyVault.withdraw(withdrawAmount, alice, alice);
        assertEq(aaveStrategyVault.balanceOf(alice), depositAmount - withdrawAmount);
        assertEq(aaveStrategyVault.totalAssets(), initialTotalAssets + depositAmount - withdrawAmount);
        assertEq(erc20Asset.balanceOf(address(aToken)), initialBalance + depositAmount - withdrawAmount);
        assertEq(erc20Asset.balanceOf(alice), withdrawAmount);
    }

    function test_AaveStrategyVault_deposit_transferAssets_does_not_change_balanceOf() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(aaveStrategyVault), depositAmount);
        vm.prank(alice);
        aaveStrategyVault.deposit(depositAmount, alice);
        uint256 shares = aaveStrategyVault.balanceOf(alice);
        assertEq(aaveStrategyVault.balanceOf(alice), shares);

        uint256 pullAmount = 30e6;
        vm.prank(address(sizeMetaVault));
        aaveStrategyVault.transferAssets(bob, pullAmount);
        assertEq(aaveStrategyVault.balanceOf(alice), shares);
        assertEq(aaveStrategyVault.totalAssets(), initialTotalAssets + depositAmount - pullAmount);
        assertEq(erc20Asset.balanceOf(address(aToken)), initialBalance + depositAmount - pullAmount);
        assertEq(erc20Asset.balanceOf(bob), pullAmount);
    }

    function test_AaveStrategyVault_deposit_transferAssets_redeem() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(aaveStrategyVault), depositAmount);
        vm.prank(alice);
        aaveStrategyVault.deposit(depositAmount, alice);
        uint256 shares = aaveStrategyVault.balanceOf(alice);
        assertEq(aaveStrategyVault.balanceOf(alice), shares);

        uint256 pullAmount = 30e6;
        vm.prank(address(sizeMetaVault));
        aaveStrategyVault.transferAssets(bob, pullAmount);
        assertEq(aaveStrategyVault.balanceOf(alice), shares);
        assertEq(aaveStrategyVault.totalAssets(), initialTotalAssets + depositAmount - pullAmount);
        assertEq(erc20Asset.balanceOf(address(aToken)), initialBalance + depositAmount - pullAmount);
        assertEq(erc20Asset.balanceOf(bob), pullAmount);

        uint256 maxRedeem = aaveStrategyVault.maxRedeem(alice);
        uint256 previewRedeem = aaveStrategyVault.previewRedeem(maxRedeem);

        vm.prank(alice);
        aaveStrategyVault.redeem(maxRedeem, alice, alice);
        assertEq(aaveStrategyVault.balanceOf(alice), shares - maxRedeem);
        assertEq(erc20Asset.balanceOf(alice), previewRedeem);
    }

    function test_AaveStrategyVault_deposit_donate_withdraw() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(aaveStrategyVault), depositAmount);
        vm.prank(alice);
        aaveStrategyVault.deposit(depositAmount, alice);
        uint256 shares = aaveStrategyVault.balanceOf(alice);
        assertEq(aaveStrategyVault.balanceOf(alice), shares);

        uint256 donation = 30e6;
        _mint(erc20Asset, bob, donation);
        vm.prank(bob);
        erc20Asset.transfer(address(aToken), donation);
        vm.prank(admin);
        pool.setLiquidityIndex(address(erc20Asset), ((depositAmount + donation) * 1e27) / depositAmount);
        assertEq(aaveStrategyVault.balanceOf(alice), shares);
        assertEq(aaveStrategyVault.balanceOf(bob), 0);
        assertEq(erc20Asset.balanceOf(address(aToken)), initialBalance + depositAmount + donation);

        uint256 maxWithdraw = aaveStrategyVault.maxWithdraw(alice);

        vm.prank(alice);
        aaveStrategyVault.withdraw(maxWithdraw, alice, alice);
        assertEq(aaveStrategyVault.balanceOf(alice), 0);
        assertGe(aaveStrategyVault.totalAssets(), initialTotalAssets);
        assertGe(erc20Asset.balanceOf(address(aToken)), initialBalance);
        assertEq(erc20Asset.balanceOf(alice), maxWithdraw);
    }

    function test_AaveStrategyVault_deposit_donate_redeem() public {
        uint256 depositAmount = 100e6;
        _mint(erc20Asset, alice, depositAmount);
        _approve(alice, erc20Asset, address(aaveStrategyVault), depositAmount);
        vm.prank(alice);
        aaveStrategyVault.deposit(depositAmount, alice);
        uint256 shares = aaveStrategyVault.balanceOf(alice);
        assertEq(aaveStrategyVault.balanceOf(alice), shares);

        uint256 donation = 30e6;
        _mint(erc20Asset, bob, donation);
        vm.prank(bob);
        erc20Asset.transfer(address(aToken), donation);
        vm.prank(admin);
        pool.setLiquidityIndex(address(erc20Asset), ((depositAmount + donation) * 1e27) / depositAmount);
        assertEq(aaveStrategyVault.balanceOf(alice), shares);
        assertEq(aaveStrategyVault.balanceOf(bob), 0);
        assertEq(erc20Asset.balanceOf(address(aToken)), initialBalance + depositAmount + donation);

        vm.prank(alice);
        aaveStrategyVault.redeem(shares, alice, alice);
        assertEq(aaveStrategyVault.balanceOf(alice), 0);
        assertGe(aaveStrategyVault.totalAssets(), initialTotalAssets);
        assertGe(erc20Asset.balanceOf(address(aToken)), initialBalance);
    }

    function test_AaveStrategyVault_initialize_wiht_address_zero_pool_must_revert() public {
        _mint(erc20Asset, alice, FIRST_DEPOSIT_AMOUNT);

        address AuthImplementation = address(new Auth());
        Auth auth =
            Auth(payable(new ERC1967Proxy(AuthImplementation, abi.encodeWithSelector(Auth.initialize.selector, bob))));

        _mint(erc20Asset, alice, FIRST_DEPOSIT_AMOUNT);

        address AaveStrategyVaultImplementation = address(new AaveStrategyVault());

        vm.expectRevert(abi.encodeWithSelector(BaseVault.NullAddress.selector));
        vm.prank(alice);
        AaveStrategyVault(
            payable(
                new ERC1967Proxy(
                    AaveStrategyVaultImplementation,
                    abi.encodeWithSelector(
                        AaveStrategyVault.initialize.selector,
                        auth,
                        erc20Asset,
                        "VAULT",
                        "VAULT",
                        FIRST_DEPOSIT_AMOUNT,
                        IPool(address(0))
                    )
                )
            )
        );
    }

    function test_AaveStrategyVault_maxDeposit_no_config() public {
        vm.prank(admin);
        pool.setConfiguration(address(erc20Asset), DataTypes.ReserveConfigurationMap({data: 0}));

        assertEq(aaveStrategyVault.maxDeposit(address(erc20Asset)), 0);
        assertEq(aaveStrategyVault.maxMint(address(erc20Asset)), 0);
        assertEq(aaveStrategyVault.maxWithdraw(address(erc20Asset)), 0);
        assertEq(aaveStrategyVault.maxRedeem(address(erc20Asset)), 0);
    }

    function test_AaveStrategyVault_maxDeposit_paused() public {
        vm.prank(admin);
        pool.setConfiguration(address(erc20Asset), DataTypes.ReserveConfigurationMap({data: 1 << 60}));

        assertEq(aaveStrategyVault.maxDeposit(address(erc20Asset)), 0);
        assertEq(aaveStrategyVault.maxMint(address(erc20Asset)), 0);
        assertEq(aaveStrategyVault.maxWithdraw(address(erc20Asset)), 0);
        assertEq(aaveStrategyVault.maxRedeem(address(erc20Asset)), 0);
    }

    function test_AaveStrategyVault_maxDeposit_supply_cap() public {
        uint8 decimals = erc20Asset.decimals();
        uint256 supplyCap = 42;

        vm.prank(admin);
        pool.setConfiguration(
            address(erc20Asset),
            DataTypes.ReserveConfigurationMap({data: (1 << 56) | (decimals << 48) | (supplyCap << 116)})
        );

        assertEq(aaveStrategyVault.maxDeposit(address(erc20Asset)), 0);
        assertEq(aaveStrategyVault.maxMint(address(erc20Asset)), 0);

        supplyCap = 100e6;

        vm.prank(admin);
        pool.setConfiguration(
            address(erc20Asset),
            DataTypes.ReserveConfigurationMap({data: (1 << 56) | (decimals << 48) | (supplyCap << 116)})
        );

        uint256 totalSupply = aToken.totalSupply();

        assertEq(aaveStrategyVault.maxDeposit(address(erc20Asset)), supplyCap - totalSupply);
        assertEq(aaveStrategyVault.maxMint(address(erc20Asset)), supplyCap - totalSupply);
    }

    function test_AaveStrategyVault_maxDeposit_totalAssetsCap_supply_cap() public {
        uint256 totalAssetsBefore = aaveStrategyVault.totalAssets();

        uint256 totalAssetsCap = 30e6;
        vm.prank(admin);
        aaveStrategyVault.setTotalAssetsCap(totalAssetsCap);

        uint8 decimals = erc20Asset.decimals();
        uint256 supplyCap = 100e6;

        vm.prank(admin);
        pool.setConfiguration(
            address(erc20Asset),
            DataTypes.ReserveConfigurationMap({data: (1 << 56) | (decimals << 48) | (supplyCap << 116)})
        );

        assertEq(aaveStrategyVault.maxDeposit(address(erc20Asset)), totalAssetsCap - totalAssetsBefore);
        assertEq(aaveStrategyVault.maxMint(address(erc20Asset)), totalAssetsCap - totalAssetsBefore);
    }
}
