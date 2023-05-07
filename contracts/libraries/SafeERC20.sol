// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "../interfaces/IDaiLikePermit.sol";
import "../interfaces/IPermit2.sol";
import "../interfaces/IWETH.sol";
import "../libraries/RevertReasonForwarder.sol";

/// @title SafeERC20
/// @notice Implements Efficient Safe Methods for ERC20
library SafeERC20 {
    error SafeTransferFailed();
    error SafeTransferFromFailed();
    error ForceApproveFailed();
    error SafeIncreaseAllowanceFailed();
    error SafeDecreaseAllowanceFailed();
    error SafePermitBadLength();
    error Permit2TransferAmountTooHigh();

    address private constant _PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    bytes4 private constant _PERMIT_LENGTH_ERROR = 0x68275857;  // SafePermitBadLength.selector
    uint256 private constant _RAW_CALL_GAS_LIMIT = 5000;
    
    
    /// @notice Returns the balance of the given token for the given account.
    /// @param token The token to check the balance of.
    /// @param account The account to check the balance for.
    /// @return tokenBalance The balance of the token.
    function safeBalanceOf(
            IERC20 token,
            address account
        ) internal view returns(uint256 tokenBalance) {
            bytes4 selector = IERC20.balanceOf.selector;
            assembly ("memory-safe") { // solhint-disable-line no-inline-assembly
                mstore(0x00, selector) // Store the selector at memory location 0x00
                mstore(0x04, account) // Store the account address at memory location 0x04
                let success := staticcall(gas(), token, 0x00, 0x24, 0x00, 0x20) // Call the balanceOf function on the token contract with the constructed data and some additional parameters
                tokenBalance := mload(0) // Load the returned value into the tokenBalance variable

                if or(iszero(success), lt(returndatasize(), 0x20)) { // If the call was not successful or the return data is less than 32 bytes
                    let ptr := mload(0x40) // Load a 32 byte pointer into memory
                    returndatacopy(ptr, 0, returndatasize()) // Copy the return data into memory starting at the pointer
                    revert(ptr, returndatasize()) // Revert with the return data
                }
            }
        }



    /// @notice Transfers a token from one address to another using either the standard or the Permit2 method
    /// @dev Ensures method do not revert or return boolean `true`, admits call to non-smart-contract.
    /// @param token The specified token to transfer.
    /// @param from The address to transfer from.
    /// @param to The address to transfer to.
    /// @param amount The amount of the specified token to transfer.
    /// @param permit2 If true use the permit2 method otherwise use the standard method.
    function safeTransferFromUniversal(
        IERC20 token,
        address from,
        address to,
        uint256 amount,
        bool permit2
    ) internal {
        if (permit2) {
            safeTransferFromPermit2(token, from, to, amount);
        } else {
            safeTransferFrom(token, from, to, amount);
        }
    }


    /// @notice Transfers a specified amount of a token from one address to another
    /// @dev Ensures method do not revert or return boolean `true`, admits call to non-smart-contract.
    /// @param token The specified token to transfer.
    /// @param from The address to transfer from.
    /// @param to The address to transfer to.
    /// @param amount The amount of the specified token to transfer.

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        bytes4 selector = token.transferFrom.selector;
        bool success;
        assembly ("memory-safe") { // solhint-disable-line no-inline-assembly
            let data := mload(0x40) // Load a new 32-byte word pointer to the memory

            mstore(data, selector) // Store the function selector in the first 4 bytes of the memory
            mstore(add(data, 0x04), from) // Store the "from" address after the selector (at position 0x04)
            mstore(add(data, 0x24), to) // Store the "to" address after the "from" address (at position 0x24)
            mstore(add(data, 0x44), amount) // Store the amount after the "to" address (at position 0x44)
            success := call(gas(), token, 0, data, 100, 0x0, 0x20) // Call the transferFrom function on the token contract with the constructed data and some additional parameters

            if success { // If the call was successful
                switch returndatasize() // Check the size of the return data
                case 0 { // If the size is 0, the call succeeded but returned no data
                    success := gt(extcodesize(token), 0) // Check that the token contract is a valid contract
                }
                default { // If the size is not 0, the call succeeded and returned some data
                    success := and(gt(returndatasize(), 31), eq(mload(0), 1)) // Check that the return value is a single boolean value indicating success
                }
            }
        }
        if (!success) revert SafeTransferFromFailed(); // If the transferFrom call failed or did not return the expected data, revert the transaction with a custom error message
    }


    /// @notice Transfers a specified amount of a token from one address to another 
    /// @dev Permit2 version of safeTransferFrom above.
    /// @param token The specified token to transfer.
    /// @param from The address to transfer from.
    /// @param to The address to transfer to.
    /// @param amount The amount of the specified token to transfer.
    function safeTransferFromPermit2(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        // Ensure the amount is not larger than the max uint160 value, which is the max value that can be used in the permit function.
        if (amount > type(uint160).max) revert Permit2TransferAmountTooHigh();

        // Get the selector for the transferFrom function of the IPermit2 interface.
        bytes4 selector = IPermit2.transferFrom.selector;
        bool success;

        assembly ("memory-safe") { // solhint-disable-line no-inline-assembly
            let data := mload(0x40) // Load a 32 byte pointer into memory

            mstore(data, selector) // Store the selector into memory
            mstore(add(data, 0x04), from) // Add the from address directly after the selector (at pos 0x04)
            mstore(add(data, 0x24), to) // Add the to address directly after the from address (at pos 0x24)
            mstore(add(data, 0x44), amount) // Add the amount directly after the to address (at pos 0x44)
            mstore(add(data, 0x64), token) // Add the token directly after the amount (at pos 0x64)

            // Call the transferFrom() function on the IPermit2 contract with the constructed data and some additional parameters.
            success := call(gas(), _PERMIT2, 0, data, 0x84, 0x0, 0x0) 

            // If the call was successful, check that the IPermit2 contract has some code deployed to it.
            if success {
                success := gt(extcodesize(_PERMIT2), 0)
            }
        }

        // Revert if the call to transferFrom() was not successful.
        if (!success) revert SafeTransferFromFailed();
    }

    
    /// @notice Transfers tokens to an address
    /// @dev Ensures method do not revert or return boolean `true`, admits call to non-smart-contract.
    /// @param token The ERC20 token intended for transfer.
    /// @param to The address to send the tokens to.
    /// @param value The amount of tokens to send.
    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        if (!_makeCall(token, token.transfer.selector, to, value)) {
            revert SafeTransferFailed();
        }
    }
    
    /// @notice Forces approval of token allowance if the initial approval fails.
    /// @dev If `approve(from, to, amount)` fails, try to `approve(from, to, 0)` before retry.
    /// @param token The token to approve.
    /// @param spender The address to grant the allowance.
    /// @param value The amount of tokens to grant the allowance for.
    function forceApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        if (!_makeCall(token, token.approve.selector, spender, value)) {
            if (
                !_makeCall(token, token.approve.selector, spender, 0) ||
                !_makeCall(token, token.approve.selector, spender, value)
            ) {
                revert ForceApproveFailed();
            }
        }
    }

    /// @notice Increases the allowance of a specified token for an address.
    /// @dev Prevents integer overflow via safeMath check.
    /// @param token The specified token to  increase the allowance.
    /// @param spender The address to increase the allowance for.
    /// @param value The amount to increase the alloance by.
    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 allowance = token.allowance(address(this), spender);
        if (value > type(uint256).max - allowance) revert SafeIncreaseAllowanceFailed();
        forceApprove(token, spender, allowance + value);
    }
    
    /// @notice Allowance decrease with safeMath check.
    /// @dev Prevents negative allowance via safeMath check
    /// @param token The token that you want to decrease the allowance for.
    /// @param spender The address that you want to decrease the allowance.
    /// @param value The amount that you want to decrease the allowance by.
    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 allowance = token.allowance(address(this), spender);
        if (value > allowance) revert SafeDecreaseAllowanceFailed();
        forceApprove(token, spender, allowance - value);
    }

    
    /// @notice Calls the permit function safely for the given token.
    /// @dev Safely calls permit for the given token.
    /// @param token The token to call permit for.
    /// @param permit The permit data.
    function safePermit(IERC20 token, bytes calldata permit) internal {
        if (!tryPermit(token, msg.sender, address(this), permit)) RevertReasonForwarder.reRevert();
    }
    
    /// @notice Calls the permit function safely for the given token, owner and spender.
    /// @dev Safely calls permit for the given token.
    /// @param token The token to call permit for.
    /// @param permit The permit data.
    /// @param owner The owner of the token.
    /// @param spender The address to grant the allowance.
    function safePermit(IERC20 token, address owner, address spender, bytes calldata permit) internal {
        if (!tryPermit(token, owner, spender, permit)) RevertReasonForwarder.reRevert();
    }
    
    /// @notice Tries to call the permit function for the given token.
    /// @dev Tries to call permit for the given token.
    /// @param token The token to call permit for.
    /// @param permit The permit data.
    /// @return success True if the permit call was successful, false otherwise.
 
    function tryPermit(IERC20 token, bytes calldata permit) internal returns(bool success) {
        return tryPermit(token, msg.sender, address(this), permit);
    }
    
    /// @notice Tries to call the permit function for the given token, owner, and spender.
    /// @dev Tries to call permit for the given token, owner, and spender.
    /// @param token The token to call permit for.
    /// @param owner The owner of the token.
    /// @param spender The address to grant the allowance.
    /// @param permit The permit data.
    /// @return success True if the permit call was successful, false otherwise.

    function tryPermit(IERC20 token, address owner, address spender, bytes calldata permit) internal returns(bool success) {
    bytes4 permitSelector = IERC20Permit.permit.selector;
    bytes4 daiPermitSelector = IDaiLikePermit.permit.selector;
    bytes4 permit2Selector = IPermit2.permit.selector;
    
    // Using assembly to handle the calldata manipulation and calling the respective permit functions
    assembly ("memory-safe") { // solhint-disable-line no-inline-assembly
        let ptr := mload(0x40) // Load free memory pointer
        
        switch permit.length // Switch based on the length of the permit calldata
        case 100 { // Compact IERC20Permit.permit representation
            mstore(ptr, permitSelector) // Store the function selector for IERC20Permit.permit
            mstore(add(ptr, 0x04), owner) // Store the owner address
            mstore(add(ptr, 0x24), spender) // Store the spender address

            // Compact IERC20Permit.permit(uint256 value, uint32 deadline, uint256 r, uint256 vs)
            {
                let deadline := shr(224, calldataload(add(permit.offset, 0x20))) // Extract the deadline value
                let vs := calldataload(add(permit.offset, 0x44)) // Extract the vs value

                // Store the required parameters for the IERC20Permit.permit call
                calldatacopy(add(ptr, 0x44), permit.offset, 0x20) // value
                mstore(add(ptr, 0x64), sub(deadline, 1)) // deadline - 1
                mstore(add(ptr, 0x84), add(27, shr(255, vs))) // v = 27 + (vs >> 255)
                calldatacopy(add(ptr, 0xa4), add(permit.offset, 0x24), 0x20) // r
                mstore(add(ptr, 0xc4), shr(1, shl(1, vs))) // s = vs >> (1 << 1)
            }
            
            // IERC20Permit.permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
            success := call(gas(), token, 0, ptr, 0xe4, 0, 0) // Call the token contract with the prepared calldata
        }
        case 72 { // Compact IDaiLikePermit.permit representation
            mstore(ptr, daiPermitSelector) // Store the function selector for IDaiLikePermit.permit
            mstore(add(ptr, 0x04), owner) // Store the owner address
            mstore(add(ptr, 0x24), spender) // Store the spender address

            // Compact IDaiLikePermit.permit(uint32 nonce, uint32 expiry, uint256 r, uint256 vs)
            {
                let expiry := shr(224, calldataload(add(permit.offset, 0x04))) // Extract the expiry value
                let vs := calldataload(add(permit.offset, 0x28)) // Extract the vs value

                // Store the required parameters for the IDaiLikePermit.permit call
                mstore(add(ptr, 0x44), shr(224, calldataload(permit.offset))) // nonce
                mstore(add(ptr,0x64), sub(expiry, 1)) // expiry - 1
                mstore(add(ptr, 0x84), true) // allowed
                mstore(add(ptr, 0xa4), add(27, shr(255, vs))) // v = 27 + (vs >> 255)
                calldatacopy(add(ptr, 0xc4), add(permit.offset, 0x08), 0x20) // r
                mstore(add(ptr, 0xe4), shr(1, shl(1, vs))) // s = vs >> (1 << 1)
            }
            
            // IDaiLikePermit.permit(address holder, address spender, uint256 nonce, uint256 expiry, bool allowed, uint8 v, bytes32 r, bytes32 s)
            success := call(gas(), token, 0, ptr, 0x104, 0, 0) // Call the token contract with the prepared calldata
        }
        case 224 { // Full IERC20Permit.permit calldata
            mstore(ptr, permitSelector) // Store the function selector for IERC20Permit.permit
            calldatacopy(add(ptr, 0x04), permit.offset, permit.length) // Copy the calldata to memory

            // IERC20Permit.permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
            success := call(gas(), token, 0, ptr, 0xe4, 0, 0) // Call the token contract with the prepared calldata
        }
        case 256 { // Full IDaiLikePermit.permit calldata
            mstore(ptr, daiPermitSelector) // Store the function selector for IDaiLikePermit.permit
            calldatacopy(add(ptr, 0x04), permit.offset, permit.length) // Copy the calldata to memory

            // IDaiLikePermit.permit(address holder, address spender, uint256 nonce, uint256 expiry, bool allowed, uint8 v, bytes32 r, bytes32 s)
            success := call(gas(), token, 0, ptr, 0x104, 0, 0) // Call the token contract with the prepared calldata
        }
        case 96 { // Compact IPermit2.permit representation
            mstore(ptr, permit2Selector) // Store the function selector for IPermit2.permit
            mstore(add(ptr, 0x04), owner) // Store the owner address
            mstore(add(ptr, 0x24), token) // Store the token address

            // Compact IPermit2.permit(uint160 amount, uint32 expiration, uint32 nonce, uint32 sigDeadline, uint256 r, uint256 vs)
            {
                calldatacopy(add(ptr, 0x50), permit.offset, 0x14) // amount
                mstore(add(ptr, 0x64), and(0xffffffffffff, sub(shr(224, calldataload(add(permit.offset, 0x14))), 1))) // expiration - 1
                mstore(add(ptr, 0x84), shr(224, calldataload(add(permit.offset, 0x18)))) // nonce
                mstore(add(ptr, 0xa4), spender) // spender address
                mstore(add(ptr, 0xc4), and(0xffffffffffff, sub(shr(224, calldataload(add(permit.offset, 0x1c))), 1))) // sigDeadline - 1
                mstore(add(ptr, 0xe4), 0x100) // signature length
                mstore(add(ptr, 0x104), 0x40) // signature offset
                calldatacopy(add(ptr, 0x124), add(permit.offset, 0x20), 0x20) // r
                calldatacopy(add(ptr, 0x144), add(permit.offset, 0x40), 0x20) // vs
            }

            // IPermit2.permit(address owner, PermitSingle calldata permitSingle, bytes calldata signature)
            success := call(gas(), _PERMIT2, 0, ptr, 0x164, 0, 0) // Call the token contract with the prepared calldata
        }
        case 352 { // Full IPermit2.permit calldata
            mstore(ptr, permit2Selector) // Store the function selector for IPermit2.permit
            calldatacopy(add(ptr, 0x04), permit.offset, permit.length) // Copy the calldata to memory

            // IPermit2.permit(address owner, PermitSingle calldata permitSingle, bytes calldata signature)
            success := call(gas(), _PERMIT2, 0, ptr, 0x164, 0, 0) // Call the token contract with the prepared calldata
        }
        default {
            mstore(ptr, _PERMIT_LENGTH_ERROR) // Store the error message
            revert(ptr, 4) // Revert with the error message
        }
    }
}

    
   /// @dev Makes a call to the specified token contract.
   /// @param token The token contract to call.
   /// @param selector The function selector for the call.
   /// @param to The address to pass to the function.
   /// @param amount The amount to pass to the function.
   /// @return success True if the call was successful, false otherwise.

    function _makeCall(
        IERC20 token,
        bytes4 selector,
        address to,
        uint256 amount
    ) private returns (bool success) {
        assembly ("memory-safe") { // solhint-disable-line no-inline-assembly
            let data := mload(0x40) // Load free memory pointer

            mstore(data, selector) // Store the function selector at the beginning of the memory
            mstore(add(data, 0x04), to) // Store the 'to' address after the function selector
            mstore(add(data, 0x24), amount) // Store the 'amount' after the 'to' address

            // Perform a call to the token contract with the prepared calldata
            success := call(gas(), token, 0, data, 0x44, 0x0, 0x20)

            if success { // If the call is successful
                // Check if there's any return data
                switch returndatasize()
                case 0 { // If there's no return data
                    // Check if the token contract actually has code
                    success := gt(extcodesize(token), 0)
                }
                default { // If there's return data
                    // Check if the return data size is greater than 31 bytes (to avoid underflow)
                    // and if the first byte of the return data is 1 (success)
                    success := and(gt(returndatasize(), 31), eq(mload(0), 1))
                }
            }
        }
    }

    
   /// @notice Safely deposits the specified amount of WETH.
   /// @dev Safely deposits the specified amount of WETH.
   /// @param weth The WETH contract.
   /// @param amount The amount of WETH to deposit.
   
    function safeDeposit(IWETH weth, uint256 amount) internal {
        if (amount > 0) {
            bytes4 selector = IWETH.deposit.selector;
            assembly ("memory-safe") { // solhint-disable-line no-inline-assembly
                mstore(0, selector) // Store the function selector at the beginning of the memory (0x0)

                // Perform a call to the weth contract with the function selector
                // and the amount of Ether to be deposited as value
                if iszero(call(gas(), weth, amount, 0, 4, 0, 0)) {
                    // If the call failed, copy the return data to memory starting at position 0x0
                    returndatacopy(0, 0, returndatasize())

                    // Revert with the copied return data as the revert reason
                    revert(0, returndatasize())
                }
            }
        }
    }


  /// @notice Safely withdraws the specified amount of WETH.
  /// @dev Safely withdraws the specified amount of WETH.
  /// @param weth The WETH contract.
  /// @param amount The amount of WETH to withdraw.

    function safeWithdraw(IWETH weth, uint256 amount) internal {
        bytes4 selector = IWETH.withdraw.selector;
        assembly ("memory-safe") {  // solhint-disable-line no-inline-assembly
            mstore(0, selector) // Store the function selector at the beginning of the memory (0x0)
            mstore(4, amount) // Store the amount directly after the selector

            // Perform a call to the weth contract with the function selector and the amount to be withdrawn
            if iszero(call(gas(), weth, 0, 0, 0x24, 0, 0)) {
                let ptr := mload(0x40) // Load the free memory pointer
                returndatacopy(ptr, 0, returndatasize()) // Copy the return data to memory starting at the free memory pointer

                // Revert with the copied return data as the revert reason
                revert(ptr, returndatasize())
            }
        }
    }



  /// @notice Safely withdraws the specified amount of WETH to the specified address.
  /// @dev Safely withdraws the specified amount of WETH to the specified address.
  /// @param weth The WETH contract.
  /// @param amount The amount of WETH to withdraw.
  /// @param to The address to send the withdrawn WETH to.

    function safeWithdrawTo(IWETH weth, uint256 amount, address to) internal {
        safeWithdraw(weth, amount);
        if (to != address(this)) {
            assembly ("memory-safe") {  // solhint-disable-line no-inline-assembly
                if iszero(call(_RAW_CALL_GAS_LIMIT, to, amount, 0, 0, 0, 0)) {
                    let ptr := mload(0x40) // Load the free memory pointer
                    returndatacopy(ptr, 0, returndatasize()) // Copy the return data to memory starting at the free memory pointer
                    
                    // Revert with the copied return data as the revert reason.
                    revert(ptr, returndatasize())
                }
            }
        }
    }
}
