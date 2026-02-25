// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract InvitationManager {
    enum InvitationStatus {
        None,
        Pending,
        Accepted,
        Rejected,
        Banned
    }
    enum InvitationType {
        Single, // 1:1
        Group, // 1:n private game
        Public // 1:n public game
    }

    struct Invitation {
        address owner;
        InvitationType invitationType;
        mapping(address => InvitationStatus) usersInvitationStatus;
    }
    // errors

    error OnlyOwnerCanAddUsers(address user);
    error UserAlreadyInvited(address user);
    error InvitationNotPending(address user);
    error OnlyOwnerCanBanUsers(address user);
    error OnlyOwnerCanUnbanUsers(address user);
    error InvalidInvitationType(InvitationType invitationType);
    error InvalidUser(address user);
    error InvalidQuestionId(bytes32 questionId);
    error UserNotInvited(address user);
    // mappings

    mapping(bytes32 => Invitation) public invitations;

    //modifiers
    modifier whenInvited(bytes32 questionId) {
        if (
            invitations[questionId].invitationType == InvitationType.Single
                || invitations[questionId].invitationType == InvitationType.Group
        ) {
            if (
                invitations[questionId].usersInvitationStatus[msg.sender] != InvitationStatus.Accepted
                    && invitations[questionId].usersInvitationStatus[msg.sender] != InvitationStatus.Pending
            ) revert UserNotInvited(msg.sender);
            invitations[questionId].usersInvitationStatus[msg.sender] = InvitationStatus.Accepted;
        }
        _;
    }

    // function isInvited(bytes32 questionId, address user) external view returns (bool) {
    //     if (invitations[questionId].invitationType == InvitationType.Single || invitations[questionId].invitationType == InvitationType.Group) {
    //     if (invitations[questionId].usersInvitationStatus[msg.sender] == InvitationStatus.Accepted || invitations[questionId].usersInvitationStatus[msg.sender] == InvitationStatus.Pending, UserNotInvited(msg.sender));
    //     invitations[questionId].usersInvitationStatus[msg.sender] = InvitationStatus.Accepted;
    //   }
    //   return true;
    // }

    function createInvitation(bytes32 questionId, address owner, InvitationType invitationType) internal {
        invitations[questionId].owner = owner;
        invitations[questionId].invitationType = invitationType;
        invitations[questionId].usersInvitationStatus[owner] = InvitationStatus.Accepted;
    }

    function addUser(bytes32 questionId, address user) external {
        if (invitations[questionId].owner != msg.sender) revert OnlyOwnerCanAddUsers(msg.sender);
        if (invitations[questionId].invitationType == InvitationType.Public) {
            // public game, no need to add users.
        } else if (
            invitations[questionId].invitationType == InvitationType.Single
                || invitations[questionId].invitationType == InvitationType.Group
        ) {
            invitations[questionId].usersInvitationStatus[user] = InvitationStatus.Pending;
        }
    }

    function addUsers(bytes32 questionId, address[] memory users) external {
        if (invitations[questionId].owner != msg.sender) revert OnlyOwnerCanAddUsers(msg.sender);
        if (invitations[questionId].invitationType != InvitationType.Group) {
            revert InvalidInvitationType(invitations[questionId].invitationType);
        }
        for (uint256 i = 0; i < users.length; i++) {
            invitations[questionId].usersInvitationStatus[users[i]] = InvitationStatus.Pending;
        }
    }

    function joinGroup(bytes32 questionId) internal {
        if (
            invitations[questionId].invitationType == InvitationType.Group
                || invitations[questionId].invitationType == InvitationType.Single
        ) {
            if (invitations[questionId].usersInvitationStatus[msg.sender] != InvitationStatus.Pending) {
                revert InvitationNotPending(msg.sender);
            }
            invitations[questionId].usersInvitationStatus[msg.sender] = InvitationStatus.Accepted;
        } else if (invitations[questionId].invitationType == InvitationType.Public) {
            invitations[questionId].usersInvitationStatus[msg.sender] = InvitationStatus.Accepted;
        }
    }

    function rejectInvitation(bytes32 questionId) public virtual {
        if (invitations[questionId].usersInvitationStatus[msg.sender] != InvitationStatus.Pending) {
            revert InvitationNotPending(msg.sender);
        }
        invitations[questionId].usersInvitationStatus[msg.sender] = InvitationStatus.Rejected;
    }

    function acceptInvitation(bytes32 questionId) public virtual {
        if (invitations[questionId].usersInvitationStatus[msg.sender] != InvitationStatus.Pending) {
            revert InvitationNotPending(msg.sender);
        }
        invitations[questionId].usersInvitationStatus[msg.sender] = InvitationStatus.Accepted;
    }

    function getInvitationStatus(bytes32 questionId, address user) external view returns (InvitationStatus) {
        return invitations[questionId].usersInvitationStatus[user];
    }

    function banUser(bytes32 questionId, address user) external virtual {
        if (invitations[questionId].owner != msg.sender) revert OnlyOwnerCanBanUsers(msg.sender);
        // can only ban user if user bet not taken or started.
        invitations[questionId].usersInvitationStatus[user] = InvitationStatus.Rejected;
    }

    function unbanUser(bytes32 questionId, address user) external virtual {
        if (invitations[questionId].owner != msg.sender) revert OnlyOwnerCanUnbanUsers(msg.sender);
        invitations[questionId].usersInvitationStatus[user] = InvitationStatus.None;
    }
}
