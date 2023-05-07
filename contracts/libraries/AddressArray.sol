/**
 * @title Library that implements address array on mapping, stores array length at 0 index.
 */
library AddressArray {
    /**
     * @dev Error messages for different scenarios
     * IndexOutOfBounds - raised when index is out of bounds
     * PopFromEmptyArray - raised when pop is called on empty array
     * OutputArrayTooSmall - raised when output array is too small
     */
    error IndexOutOfBounds();
    error PopFromEmptyArray();
    error OutputArrayTooSmall();

    /**
     * @dev Data struct containing raw mapping.
     */
    struct Data {
        mapping(uint256 => uint256) _raw;
    }

    /**
     * @dev Returns length of the array.
     * @param self The `Data` struct containing raw mapping
     * @return length The length of the array.
     */
    function length(Data storage self) internal view returns (uint256 length) {
        length = self._raw[0] >> 160;
    }

    /**
     * @dev Returns data item from `self` storage at `i`.
     * @param self The `Data` struct containing raw mapping
     * @param i The index of the item to retrieve
     * @return address The address at the specified index
     */
    function at(Data storage self, uint256 i) internal view returns (address) {
        return address(uint160(self._raw[i]));
    }

    /**
     * @dev Returns list of addresses from storage `self`.
     * @param self The `Data` struct containing raw mapping
     * @return arr The list of addresses from storage `self`
     */
    function get(Data storage self) internal view returns (address[] memory arr) {
        uint256 lengthAndFirst = self._raw[0];
        arr = new address[](lengthAndFirst >> 160);
        _get(self, arr, lengthAndFirst);
    }

    /**
     * @dev Puts list of addresses from `self` storage into `output` array.
     * @param self The `Data` struct containing raw mapping
     * @param output The output array to store the list of addresses from `self`
     * @return output The output array containing the list of addresses from `self`
     */
    function get(Data storage self, address[] memory output) internal view returns (address[] memory) {
        return _get(self, output, self._raw[0]);
    }

    function _get(
        Data storage self,
        address[] memory output,
        uint256 lengthAndFirst
    ) private view returns (address[] memory) {
        uint256 len = lengthAndFirst >> 160;
        if (len > output.length) revert OutputArrayTooSmall();
        if (len > 0) {
            output[0] = address(uint160(lengthAndFirst));
            unchecked {
                for (uint256 i = 1; i < len; i++) {
                    output[i] = address(uint160(self._raw[i]));
                }
            }
        }
        return output;
    }

    /**
     * @dev Adds `account` to the end of the array in storage `self`.
     * @param self The `Data` struct containing raw mapping
     * @param account The address to be added to the end of the array in storage `self`
     * @return len The length of the array after adding the address
     */
    function push(Data storage self, address account) internal returns (uint256) {
        unchecked {
            uint256 lengthAndFirst = self._raw[0];
            uint256 len = lengthAndFirst >> 160;
            if (len == 0) {
                self._raw[0] = (1 << 160) + uint160(account);
            } else {
                self._raw[0] = lengthAndFirst + (1 << 160);
                self._raw[len] = uint160(account);
            }
            return len + 1;
        }
    }

  /**
     * @dev Array pop back operation for storage `self`.
     * @param self The address array in storage to pop an element from.
     */
    function pop(Data storage self) internal {
        unchecked {
            uint256 lengthAndFirst = self._raw[0];
            uint256 len = lengthAndFirst >> 160;
            if (len == 0) revert PopFromEmptyArray();
            self._raw[len - 1] = 0;
            if (len > 1) {
                self._raw[0] = lengthAndFirst - (1 << 160);
            }
        }
    }

    /**
     * @dev Set element for storage `self` at `index` to `account`.
     * @param self The address array in storage to set an element in.
     * @param index The index of the element to set.
     * @param account The new address to set at the specified index.
     */
    function set(Data storage self, uint256 index, address account) internal {
        uint256 len = length(self);
        if (index >= len) revert IndexOutOfBounds();

        if (index == 0) {
            self._raw[0] = (len << 160) | uint160(account);
        } else {
            self._raw[index] = uint160(account);
        }
    }
}
