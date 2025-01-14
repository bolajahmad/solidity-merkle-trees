// SPDX-License-Identifier: Apache2
pragma solidity ^0.8.17;

import "./MerkleMultiProof.sol";

/// @title A representation of a MerkleMountainRange tree
struct MmrLeaf {
    uint256 k_index;            // the leftmost index of a node
    uint256 mmr_pos;            // The position in the tree
    bytes32 hash;               // The hash of the position in the tree
}

/**
 * @title A Merkle Mountain Range proof library
 * @author Polytope Labs
 * @notice Use this library to verify the node(s) of a merkle tree
 * @dev read the Merkle mountain research https://research.polytope.technology/merkle-mountain-range-multi-proofs
 */
library MerkleMountainRange {
    /// @title Verify that merkle proof is accurate
    /// @notice This calls calculateRoot(...) under the hood
    /// @param root hash of the Merkle's root node
    /// @param proof a list of nodes required for the proof to be verified, proof nodes
    /// @param leaves a list of merkle nodes to provide proof for
    /// @return boolean representing a match between calculated root and provided root
    function verifyProof(
        bytes32 root,
        bytes32[] memory proof,
        MmrLeaf[] memory leaves,
        uint256 mmrSize
    ) public pure returns (bool) {
        return root == calculateRoot(proof, leaves, mmrSize);
    }

    /// @title Calculate merkle root 
    /// @notice this method allows computing the root hash of a merkle tree using Merkle Mountain Range
    /// @param proof a list of nodes that must be traversed to reach the root node, called proof nodes
    /// @param leaves a list of merkle nodes to provide proof for
    /// @param mmrSize 
    /// @return bytes32 hash of the computed root node
    function calculateRoot(
        bytes32[] memory proof,
        MmrLeaf[] memory leaves,
        uint256 mmrSize
    ) public pure returns (bytes32) {
        uint256[] memory peaks = getPeaks(mmrSize);
        bytes32[] memory peakRoots = new bytes32[](peaks.length);
        uint256 pc = 0;
        uint256 prc = 0;

        for (uint256 p = 0; p < peaks.length; p++) {
            uint256 peak = peaks[p];
            MmrLeaf[] memory peakLeaves = new MmrLeaf[](0);
            if (leaves.length > 0) {
                (peakLeaves, leaves) = leavesForPeak(leaves, peak);
            }

            if (peakLeaves.length == 0) {
                if (proof.length == pc) {
                    break;
                } else {
                    peakRoots[prc] = proof[pc];
                    prc++;
                    pc++;
                }
            } else if (peakLeaves.length == 1 && peakLeaves[0].mmr_pos == peak) {
                peakRoots[prc] = peakLeaves[0].hash;
                prc++;
            } else {
                (peakRoots[prc], pc) = calculatePeakRoot(peakLeaves, proof, peak, pc);
                prc++;
            }
        }

        prc--;
        while (prc != 0) {
            bytes32 right = peakRoots[prc];
            prc--;
            bytes32 left = peakRoots[prc];
            peakRoots[prc] = keccak256(abi.encodePacked(right, left));
        }

        return peakRoots[0];
    }

    /// @title calculate root hash of a sub peak of the merkle mountain
    /// @param peakLeaves  a list of nodes to provide proof for 
    /// @param proof   a list of node hashes to traverse to compute the peak root hash
    /// @param peak
    /// @param pc
    /// @return peakRoot a tuple containing the peak root hash, and the peak root position in the merkle
    function calculatePeakRoot(
        MmrLeaf[] memory peakLeaves,
        bytes32[] memory proof,
        uint256 peak,
        uint256 pc
    ) internal pure returns (bytes32, uint256)  {
        uint256[] memory current_layer;
        Node[] memory leaves;
        (leaves, current_layer) = mmrLeafToNode(peakLeaves);
        uint256 height = posToHeight(uint64(peak));
        Node[][] memory layers = new Node[][](height);

        for (uint256 i = 0; i < height; i++) {
            uint256[] memory siblings = siblingIndices(current_layer);
            uint256[] memory diff = difference(siblings, current_layer);
            if (diff.length == 0) {
                break;
            }

            layers[i] = new Node[](diff.length);
            for (uint256 j = 0; j < diff.length; j++) {
                layers[i][j] = Node(diff[j], proof[pc]);
                pc++;
            }

            current_layer = parentIndices(siblings);
        }

        return (MerkleMultiProof.calculateRoot(layers, leaves), pc);
    }

    /**
     * @notice difference ensures all nodes have a sibling.
     * @dev left and right are designed to be equal length array
     * @param left a list of hashes
     * @param right a list of hashes to compare
     * @return uint256[] a new array with difference 
     */
    function difference(uint256[] memory left, uint256[] memory right) internal pure returns (uint256[] memory) {
        uint256[] memory diff = new uint256[](left.length);
        uint256 d = 0;
        for (uint256 i = 0; i < left.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < right.length; j++) {
                if (left[i] == right[j]) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                diff[d] = left[i];
                d++;
            }
        }

        uint256[] memory out = new uint256[](d);
        uint256 k = 0;
        while (k < d) {
            out[k] = diff[k];
            k++;
        }

        return out;
    }

    /**
     * @dev calculates the index of each sibling index of the proof nodes
     * @dev proof nodes are the nodes that will be traversed to estimate the root hash
     * @param indices a list of proof nodes indices
     * @return uint256[] a list of sibling indices
     */
    function siblingIndices(uint256[] memory indices) internal pure returns (uint256[] memory) {
        uint256[] memory siblings = new uint256[](indices.length);

        for (uint256 i = 0; i < indices.length; i++) {
            uint256 index = indices[i];
            if (index == 0) {
                siblings[i] = index + 1;
            } else if (index % 2 == 0) {
                siblings[i] = index + 1;
            } else {
                siblings[i] = index - 1;
            }
        }

        return siblings;
    }

    /**
     * @title Compute Parent Indices
     * @dev Used internally to calculate the indices of the parent nodes of the provided proof nodes
     * @param indices a list of indices of proof nodes in a merkle mountain 
     * @return uint256[] a list of parent indices for each index provided
     */
    function parentIndices(uint256[] memory indices) internal pure returns (uint256[] memory) {
        uint256[] memory  parents = new uint256[](indices.length);

        for (uint256 i = 0; i < indices.length; i++) {
            parents[i] = indices[i] / 2;
        }

        return parents;
    }

    /**
     * @title Convert Merkle mountain Leaf to a Merkle Node
     * @param leaves list of merkle mountain range leaf
     * @return A tuple with the list of merkle nodes and the list of nodes at 0 and 1 respectively
     */
    function mmrLeafToNode(MmrLeaf[] memory leaves) internal pure returns (Node[] memory, uint256[] memory) {
        uint256 i = 0;
        Node[] memory nodes = new Node[](leaves.length);
        uint256[] memory indices = new uint256[](leaves.length);
        while (i < leaves.length) {
            nodes[i] = Node(leaves[i].k_index, leaves[i].hash);
            indices[i] = leaves[i].k_index;
            i++;
        }

        return (nodes, indices);
    }

    /**
     * @title Get a meountain peak's leaves
     * @notice this splits the leaves into either side of the peak [left & right]
     * @param leaves a list of mountain merkle leaves, for a subtree
     * @param peak the peak index of the root of the subtree
     * @return A tuple of 2 arrays of mountain merkle leaves. Index 1 and 2 represent left and right of the peak respectively
     */
    function leavesForPeak(
        MmrLeaf[] memory leaves,
        uint256 peak
    ) internal pure returns (MmrLeaf[] memory, MmrLeaf[] memory) {
        uint256 p = 0;
        for (;p < leaves.length; p++) {
            if (peak < leaves[p].mmr_pos) {
                break;
            }
        }

        uint256 len = p == 0 ? 0 : p;
        MmrLeaf[] memory left = new MmrLeaf[](len);
        MmrLeaf[] memory right = new MmrLeaf[](leaves.length - len);

        uint256 i = 0;
        while (i < left.length) {
            left[i] = leaves[i];
            i++;
        }

        uint256 j = 0;
        while (i < leaves.length) {
            right[j] = leaves[i];
            i++;
            j++;
        }

        return (left, right);
    }

    /**
     * @title Merkle mountain peaks computer
     * @notice Used internally to calculate a list of subtrees from the merkle mountain range
     * @param mmrSize the size of the merkle mountain range, or the height of the tree
     * @return uint265[] a list of the peak positions
     */
    function getPeaks(uint256 mmrSize) internal pure returns (uint256[] memory) {
        uint256 height;
        uint256 pos;
        (height, pos) = leftPeakHeightPos(mmrSize);
        uint256[] memory positions = new uint256[](height);
        uint256 p = 0;
        positions[p] = pos;
        p++;

        while (height > 0) {
            uint256 _height;
            uint256 _pos;
            (_height, _pos) = getRightPeak(height, pos, mmrSize);
            if (_height == 0 && _pos == 0) {
                break;
            }

            height = _height;
            pos = _pos;
            positions[p] = pos;
            p++;
        }

        // copy array to new one, sigh solidity.
        uint256 i = 0;
        uint256[] memory out = new uint256[](p);
        while (i < p) {
            out[i] = positions[i];
            i++;
        }

        return out;
    }

    function getRightPeak(uint256 height, uint256 pos, uint256 mmrSize) internal pure returns (uint256, uint256) {
        pos += siblingOffset(height);

        while (pos > (mmrSize - 1)) {
            if (height == 0) {
                return (0, 0);
            }
            height -= 1;
            pos -= parentOffset(height);
        }

        return (height, pos);
    }

    function leftPeakHeightPos(uint256 mmrSize) internal pure returns (uint256, uint256) {
        uint256 height = 1;
        uint256 prevPos = 0;
        uint256 pos = getPeakPosByHeight(height);
        while (pos < mmrSize) {
            height += 1;
            prevPos = pos;
            pos = getPeakPosByHeight(height);
        }

        return (height - 1, prevPos);
    }

    function getPeakPosByHeight(uint256 height) internal pure returns (uint256) {
        return (1 << (height + 1)) - 2;
    }

    function posToHeight(uint64 pos) internal pure returns (uint64) {
        pos += 1;

        while (!allOnes(pos)) {
            pos = jumpLeft(pos);
        }

        return (64 - countLeadingZeros(pos) - 1);

    }

    function siblingOffset(uint256 height) internal pure returns (uint256) {
        return (2 << height) - 1;
    }

    function parentOffset(uint256 height) internal pure returns (uint256) {
        return 2 << height;
    }

    function allOnes(uint64 pos) internal pure returns (bool) {
        return pos != 0 && countZeroes(pos) == countLeadingZeros(pos);
    }

    function jumpLeft(uint64 pos) internal pure returns (uint64) {
        uint64 len = 64 - countLeadingZeros(pos);
        uint64 msb = uint64(1 << (len - 1));
        return (pos - (msb - 1));
    }

    function countLeadingZeros(uint64 num) internal pure returns (uint64) {
        uint64 size = 64;
        uint64 count = 0;
        uint64  msb = uint64(1 << (size - 1));
        for (uint64 i = 0; i < size; i++) {
            if (((num << i) & msb) != 0) {
                break;
            }
            count++;

        }

        return count;
    }

    function countZeroes(uint64 num) internal pure returns (uint256) {
        return 64 - countOnes(num);
    }

    function countOnes(uint64 num) internal pure returns (uint64) {
        uint64 count = 0;

        while (num !=  0) {
            num &= (num - 1);
            count++;
        }

        return count;
    }

    /// Merge a list of nodes into one node. The result will need to be sorted aftewards
    /// @dev 
    /// @param out the array to merge the nodes into
    /// @param arr1 one of the list of nodes to merge
    /// @param arr2 the other of the list of nodes to merge
    function mergeArrays(
        Node[] memory out,
        Node[] memory arr1,
        Node[] memory arr2
    ) internal pure {
        // merge the two arrays
        uint256 i = 0;
        while (i < arr1.length) {
            out[i] = arr1[i];
            i++;
        }

        uint256 j = 0;
        while (j < arr2.length) {
            out[i] = arr2[j];
            i++;
            j++;
        }
    }

    /**
     * @title Sort a list of data using quick sort algorithm 
     * @notice this is an overloaded function, but they all do the same thing 
     * @param arr list of data to sort. In this case, it's a merkle node 
     * @param left leftmost position on the list, or lowest point 
     * @param right rightmost position on the list, or highest point 
     */
    function quickSort(
        Node[] memory arr,
        uint256 left,
        uint256 right
    ) internal pure {
        uint256 i = left;
        uint256 j = right;
        if (i == j) return;
        uint256 pivot = arr[uint256(left + (right - left) / 2)].k_index;
        while (i <= j) {
            while (arr[uint256(i)].k_index < pivot) i++;
            while (pivot < arr[uint256(j)].k_index) if (j > 0) j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (
                arr[uint256(j)],
                arr[uint256(i)]
                );
                i++;
                if (j > 0) j--;
            }
        }
        if (left < j) quickSort(arr, left, j);
        if (i < right) quickSort(arr, i, right);
    }

  /**
     * @title Sort a list of data using quick sort algorithm
     * @notice this is an overloaded function, but they all do the same thing
     * @param arr list of data to sort. In this case, it's a list of node hashes
     * @param left leftmost position on the list, or lowest point
     * @param right rightmost position on the list, or highest point
     */
    function quickSort(
        uint256[] memory arr,
        uint256 left,
        uint256 right
    ) internal pure {
        uint256 i = left;
        uint256 j = right;
        if (i == j) return;
        uint256 pivot = arr[uint256(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint256(i)] < pivot) i++;
            while (pivot < arr[uint256(j)]) if (j > 0) j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (
                arr[uint256(j)],
                arr[uint256(i)]
                );
                i++;
                if (j > 0) j--;
            }
        }
        if (left < j) quickSort(arr, left, j);
        if (i < right) quickSort(arr, i, right);
    }

  /**
     * @title Sort a list of data using quick sort algorithm
     * @notice this is an overloaded function, but they all do the same thing
     * @param arr list of data to sort. In this case, it's a merkle mountain node
     * @param left leftmost position on the list, or lowest point
     * @param right rightmost position on the list, or highest point
     */
    function quickSort(
        MmrLeaf[] memory arr,
        uint256 left,
        uint256 right
    ) internal pure {
        uint256 i = left;
        uint256 j = right;
        if (i == j) return;
        uint256 pivot = arr[uint256(left + (right - left) / 2)].mmr_pos;
        while (i <= j) {
            while (arr[uint256(i)].mmr_pos < pivot) i++;
            while (pivot < arr[uint256(j)].mmr_pos) if (j > 0) j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (
                arr[uint256(j)],
                arr[uint256(i)]
                );
                i++;
                if (j > 0) j--;
            }
        }
        if (left < j) quickSort(arr, left, j);
        if (i < right) quickSort(arr, i, right);
    }

    /// @title Integer log2
    /// @param x Integer value, calculate the log2 and floor it
    /// @return uint the floored result
    /// @notice if x is nonzero floored value is returned, otherwise 0. 
    /// @notice This is the same as the location of the highest set bit.
    /// @dev Consumes 232 gas. This could have been an 3 gas EVM opcode though.
    function floorLog2(uint256 x) internal pure returns (uint256 r) {
        assembly {
            r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffff, shr(r, x))))
            r := or(r, shl(3, lt(0xff, shr(r, x))))
            r := or(r, shl(2, lt(0xf, shr(r, x))))
            r := or(r, shl(1, lt(0x3, shr(r, x))))
            r := or(r, lt(0x1, shr(r, x)))
        }
    }
}