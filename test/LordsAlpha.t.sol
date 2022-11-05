// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/LordsAlpha.sol";

contract LordsAlphaTest is Test {
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }
    LordsAlpha public lordsalpha;
    bytes32 root1 = 0x3e82b7d669c35b1793116c650619d6ad9d8ed8bafb2ec0d1d614fe4f333ad9d5;
    bytes32 root2 = 0x538d0c15fdbd4471a38ba784f90b5a13c7d7ba84e4ad3ba96f0b8f984f13cafb;

    address internal add1 = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;
    address internal add2 = 0x71bb9b545330c7958C1b4D5ecDB74b724afe957C;
    // contains add1
    bytes32[] internal proof1 = [bytes32(0xedc8cf70ab67dc4b181347b7137477d7f9ef1829f4da8bdbdf438f96e558a0ef),0xbfa96226c0ca390b353f10c0ee96e2552a5927c149b200e85f70f987f84b4ae1];
    // contains add2
    bytes32[] internal proof2 = [bytes32(0xed4acf49e00e7c42a17eda918462a24157d66265daa43892e9cfeec15f8b4e03),0x56aafd6f6efdf09e3ad94bbd7fe113aecabca844bf7b880c1afce87b499473e8];

    uint32 startTime = 1666932588;

    mapping(address => bool) seenAddresses;

    function setUp() public {
        lordsalpha = new LordsAlpha(root1, root2, startTime);
    }

    function testInitialization() public {
        assertEq(lordsalpha.MAX_SUPPLY(), uint256(555));
        assertEq(lordsalpha.MINT_PRICE(), 0.18 ether);
        assertEq(lordsalpha.MAX_PER_WALLET_PER_PHASE(), 2);
        assertEq(lordsalpha.MINIMUM_TIME_STAKED_FOR_PREMIUM_REDEMPTION(), 7776000);
        assertEq(lordsalpha.totalSupply(1), 55);
        assertEq(lordsalpha.balanceOf(address(this), 1), 55);
        (bytes32 _root1, uint64 _startTime1, uint64 _endTime1) = lordsalpha.phaseOneDetails();
        (bytes32 _root2, uint64 _startTime2, uint64 _endTime2) = lordsalpha.phaseTwoDetails();
        assertEq(_root1, root1);
        assertEq(_root2, root2);
        assertEq(_startTime1, startTime);
        assertEq(_endTime1, startTime + 7200); // 2 hrs = 7200 sec
        assertEq(_startTime2, startTime + 7200); // phase one ends and phase 2 begins during same block
        assertEq(_endTime2, startTime + 86400); // public starts one day after startTime 
    }

    function testMintAllowlistFailures() public {
        // public has not started yet
        hoax(add1);
        vm.expectRevert(AllowlistSaleNotActive.selector);
        lordsalpha.mintAllowlist{value: 0.36 ether}(proof1, 2);

        // invalid proof
        vm.warp(startTime + 60);
        hoax(address(5));
        vm.expectRevert(InvalidProof.selector);
        lordsalpha.mintAllowlist{value: 0.36 ether}(proof1, 2);

        // wrong value sent
        hoax(add1);
        vm.expectRevert(WrongValueSent.selector);
        lordsalpha.mintAllowlist{value: 0.18 ether}(proof1, 2);

        // exceeds max per wallet
        startHoax(add1);
        lordsalpha.mintAllowlist{value: 0.18 ether}(proof1, 1);
        lordsalpha.mintAllowlist{value: 0.18 ether}(proof1, 1);
        vm.expectRevert(ExceedMaxPerWallet.selector);
        lordsalpha.mintAllowlist{value: 0.18 ether}(proof1, 1);

        // not bypassable by transfers
        lordsalpha.safeTransferFrom(add1, address(5), 1, 2, "");
        vm.expectRevert(ExceedMaxPerWallet.selector);
        lordsalpha.mintAllowlist{value: 0.18 ether}(proof1, 1);
    }

    function testMintMaxSupply(address[250] memory _addresses) public {
        vm.warp(startTime + 2 days);
        for (uint256 i = 0; i < _addresses.length; i++) {
            address _address = _addresses[i];
            uint size;
            assembly { size := extcodesize(_address) }
            vm.assume(size == 0);
            vm.assume(_address != address(0));
            vm.assume(!seenAddresses[_address]);
            hoax(_address);
            lordsalpha.mintPublic{value: 0.36 ether}(2);
            seenAddresses[_address] = true;
        }

        vm.assume(!seenAddresses[address(7)]);
        hoax(address(7));
        vm.expectRevert(ExceedMaxSupply.selector);
        lordsalpha.mintPublic{value: 0.18 ether}(1);
    }

    function testMintPublicFailures() public {
        // during phase one window
        vm.warp(startTime + 1 hours);
        startHoax(add1);
        vm.expectRevert(PublicSaleNotStarted.selector);
        lordsalpha.mintPublic{value: 0.36 ether}(2);

        // during phase 2 window
        vm.warp(startTime + 3 hours);
        vm.expectRevert(PublicSaleNotStarted.selector);
        lordsalpha.mintPublic{value: 0.36 ether}(2);
        
        // during public window
        vm.warp(startTime + 25 hours);

        // wrong value sent
        vm.expectRevert(WrongValueSent.selector);
        lordsalpha.mintPublic{value: 0.18 ether}(2);

        // exceeds max per wallet
        lordsalpha.mintPublic{value: 0.18 ether}(1);
        lordsalpha.mintPublic{value: 0.18 ether}(1);
        vm.expectRevert(ExceedMaxPerWallet.selector);
        lordsalpha.mintPublic{value: 0.18 ether}(1);
    }

    function testSingleMintAllowList() public {
        vm.warp(startTime);
        hoax(add1);
        lordsalpha.mintAllowlist{value: 0.18 ether}(proof1, 1);
        hoax(add1);
        lordsalpha.mintAllowlist{value: 0.18 ether}(proof1, 1);

        hoax(add2);
        vm.expectRevert(InvalidProof.selector);
        lordsalpha.mintAllowlist{value: 0.18 ether}(proof2, 1);

        vm.warp(startTime + 3 hours);
        hoax(add2);
        lordsalpha.mintAllowlist{value: 0.18 ether}(proof2, 1);
        hoax(add2);
        lordsalpha.mintAllowlist{value: 0.18 ether}(proof2, 1);

        hoax(add1);
        vm.expectRevert(InvalidProof.selector);
        lordsalpha.mintAllowlist{value: 0.18 ether}(proof1, 1);

        assertEq(lordsalpha.balanceOf(add2, 1), 2);
        assertEq(lordsalpha.balanceOf(add1, 1), 2);
        assertEq(lordsalpha.totalSupply(1), 59);
    }

    function testMultipleMintAllowList() public {
        vm.warp(startTime);
        hoax(add1);
        lordsalpha.mintAllowlist{value: 0.36 ether}(proof1, 2);

        hoax(add2);
        vm.expectRevert(InvalidProof.selector);
        lordsalpha.mintAllowlist{value: 0.36 ether}(proof2, 2);

        vm.warp(startTime + 3 hours);
        hoax(add2);
        lordsalpha.mintAllowlist{value: 0.36 ether}(proof2, 2);

        hoax(add1);
        vm.expectRevert(InvalidProof.selector);
        lordsalpha.mintAllowlist{value: 0.36 ether}(proof1, 2);

        assertEq(lordsalpha.balanceOf(add2, 1), 2);
        assertEq(lordsalpha.balanceOf(add1, 1), 2);
        assertEq(lordsalpha.totalSupply(1), 59);
    }

    function testMintPublic() public {
        vm.warp(startTime + 24 hours);

        hoax(address(5));
        lordsalpha.mintPublic{value: 0.36 ether}(2);
    }

    function testStake() public {
        uint256 stakeStartTime = startTime + 24 hours;
        vm.warp(stakeStartTime);
        startHoax(address(5));
        lordsalpha.mintPublic{value: 0.36 ether}(2);

        // stake one
        lordsalpha.stakeAlphaPass(1);
        assertEq(lordsalpha.balanceOf(address(5), 1), 1);
        assertEq(lordsalpha.balanceOf(address(lordsalpha), 1), 1);
        (uint16 numStaked, uint64 timeStarted) = lordsalpha.stakeDetailsFor(address(5));
        assertEq(numStaked, 1);
        assertEq(timeStarted, 0);

        // stake a second
        lordsalpha.stakeAlphaPass(1);
        assertEq(lordsalpha.balanceOf(address(5), 1), 0);
        assertEq(lordsalpha.balanceOf(address(lordsalpha), 1), 2);
        (uint16 numStaked2, uint64 timeStarted2) = lordsalpha.stakeDetailsFor(address(5));
        assertEq(numStaked2, 2);
        assertEq(timeStarted2, stakeStartTime);

        // stake 2
        changePrank(address(4));
        vm.deal(address(4), 1 ether);
        lordsalpha.mintPublic{value: 0.36 ether}(2);

        lordsalpha.stakeAlphaPass(2);
        assertEq(lordsalpha.balanceOf(address(4), 1), 0);
        assertEq(lordsalpha.balanceOf(address(lordsalpha), 1), 4);
        (uint16 numStaked3, uint64 timeStarted3) = lordsalpha.stakeDetailsFor(address(4));
        assertEq(numStaked3, 2);
        assertEq(timeStarted3, stakeStartTime);

        // stake more than 2
        changePrank(address(6));
        vm.deal(address(6), 1 ether);
        lordsalpha.mintPublic{value: 0.36 ether}(2);
        changePrank(address(7));
        vm.deal(address(7), 1 ether);
        lordsalpha.mintPublic{value: 0.36 ether}(2);
        lordsalpha.safeTransferFrom(address(7), address(6), 1, 2, "");

        uint256 newTime = 1667019537;
        vm.warp(newTime);
        changePrank(address(6));
        lordsalpha.stakeAlphaPass(4);
        assertEq(lordsalpha.balanceOf(address(6), 1), 0);
        assertEq(lordsalpha.balanceOf(address(lordsalpha), 1), 8);
        (uint16 numStaked4, uint64 timeStarted4) = lordsalpha.stakeDetailsFor(address(6));
        assertEq(numStaked4, 4);
        assertEq(timeStarted4, newTime);

        changePrank(address(7));
        vm.expectRevert(abi.encodePacked("ERC1155: insufficient balance for transfer"));
        lordsalpha.stakeAlphaPass(4);
    }

    function testUnstake() public {
        testStake();

        changePrank(address(6));
        vm.expectRevert(NotEnoughStaked.selector);
        lordsalpha.withdrawAlphaPass(5);

        lordsalpha.withdrawAlphaPass(2);
        (uint16 numStaked2, uint64 timeStarted2) = lordsalpha.stakeDetailsFor(address(6));
        assertEq(numStaked2, 2);
        assertEq(timeStarted2, 1667019537);

        lordsalpha.withdrawAlphaPass(2);
        (uint16 numStaked, uint64 timeStarted) = lordsalpha.stakeDetailsFor(address(6));
        assertEq(numStaked, 0);
        assertEq(timeStarted, 0);
    }

    function testRedeemForPremium() public {
        testStake();

        changePrank(address(6));
        vm.warp(1667019537 + 91 days);
        lordsalpha.redeemForPremium();
        (uint16 numStaked, uint64 timeStarted) = lordsalpha.stakeDetailsFor(address(6));
        assertEq(numStaked, 2);
        assertEq(timeStarted, 1667019537 + 91 days);
        assertEq(lordsalpha.balanceOf(address(6), 2), 1);
        assertEq(lordsalpha.balanceOf(address(lordsalpha), 1), 6);

        vm.warp(1667019537 + 181 days);
        lordsalpha.redeemForPremium();
        (uint16 numStaked2, uint64 timeStarted2) = lordsalpha.stakeDetailsFor(address(6));
        assertEq(numStaked2, 0);
        assertEq(timeStarted2, 0);
        assertEq(lordsalpha.balanceOf(address(6), 2), 2);
        assertEq(lordsalpha.balanceOf(address(lordsalpha), 1), 4);
    }

    function testSetUri() public {
        string memory newUri = "ipfs://QmThisIsNew/";
        assertEq(keccak256(abi.encodePacked("QmHashLordsAlpha/1.json")), keccak256(abi.encodePacked(lordsalpha.uri(1))));
        hoax(add1);
        vm.expectRevert(abi.encodePacked("Ownable: caller is not the owner"));
        lordsalpha.setUri(newUri);
        hoax(lordsalpha.owner());
        lordsalpha.setUri(newUri);
        string memory expectedUri = "ipfs://QmThisIsNew/1.json";
        assertEq(keccak256(abi.encodePacked(expectedUri)), keccak256(abi.encodePacked(lordsalpha.uri(1))));
    }

    function testWithdraw() public {

    }
}
