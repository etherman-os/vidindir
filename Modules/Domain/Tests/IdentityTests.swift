import Foundation
import Testing
@testable import VidindirDomain

@Suite("Deterministic domain identities")
struct IdentityTests {
    @Test func fixedPersonalIdentitiesMatchThePublishedContract() {
        #expect(VidindirIdentity.personalWorkspace.description ==
            "4ce29601-0ff5-55fb-995f-2329e01734d8")
        #expect(VidindirIdentity.personalInbox.description ==
            "4bb48462-deda-5c43-afd5-03031290ff60")
        #expect(VidindirIdentity.inboxCollection(
            workspaceID: VidindirIdentity.personalWorkspace
        ) == VidindirIdentity.personalInbox)
    }

    @Test func relationshipIdentitiesUseTheFrozenUUIDv5Names() throws {
        let mediaID = try #require(MediaItemID(
            uuidString: "11111111-2222-3333-4444-555555555555"
        ))
        let membership = VidindirIdentity.collectionMembership(
            workspaceID: VidindirIdentity.personalWorkspace,
            collectionID: VidindirIdentity.personalInbox,
            mediaItemID: mediaID
        )
        let favorite = VidindirIdentity.favorite(
            workspaceID: VidindirIdentity.personalWorkspace,
            mediaItemID: mediaID
        )

        #expect(membership.description == "64a4c3b4-0fe5-5baa-9516-c1793e7614ca")
        #expect(favorite.description == "fc86e3c8-af3c-5190-934d-445a3a940a2e")
    }

    @Test func typedIDsEncodeAsCanonicalStrings() throws {
        let id = try #require(MediaItemID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        ))
        let data = try JSONEncoder().encode(id)
        #expect(String(decoding: data, as: UTF8.self) ==
            #""aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee""#)
        #expect(try JSONDecoder().decode(MediaItemID.self, from: data) == id)
    }
}
