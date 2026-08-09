package tw.stsa.memberapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import tw.stsa.memberapp.auth.Profile

/**
 * Every case goes through decoding rather than the constructor, which is how the
 * app builds a Profile anyway — the claim mapping is the part worth pinning.
 */
private fun makeProfile(json: String): Profile = Profile.decode(json)

class ProfileDecodingTest {

    @Test
    fun `maps authentik snake case claims`() {
        val profile = makeProfile(
            """
            {
              "sub": "abc-123",
              "email": "kimi@u.nus.edu",
              "email_verified": true,
              "given_name": "Kimi",
              "preferred_username": "kimiyang"
            }
            """
        )

        assertEquals("abc-123", profile.sub)
        assertEquals(true, profile.emailVerified)
        assertEquals("Kimi", profile.givenName)
        assertEquals("kimiyang", profile.preferredUsername)
    }

    /**
     * authentik omits `groups` entirely when a user is in none. That has to
     * decode as "no groups" rather than throwing, or sign-in fails outright.
     */
    @Test
    fun `treats absent groups as empty rather than failing`() {
        val profile = makeProfile("""{"sub": "abc-123"}""")

        assertTrue(profile.groups.isEmpty())
        assertFalse(profile.isOfficer)
    }

    /** `sub` is the one claim the app cannot work without. */
    @Test(expected = Exception::class)
    fun `requires sub`() {
        makeProfile("""{"email": "kimi@u.nus.edu"}""")
    }

    /**
     * authentik sends more claims than this app models and adds to them between
     * releases, so an unknown one must not fail the decode.
     */
    @Test
    fun `ignores claims the app does not model`() {
        val profile = makeProfile("""{"sub": "abc", "acr": "goauthentik.io/x", "aud": "y"}""")

        assertEquals("abc", profile.sub)
    }
}

class ProfileDisplayNameTest {

    /** The fallback chain is ordered by how authentik populates the claims. */
    @Test
    fun `prefers name over everything else`() {
        val profile = makeProfile(
            """{"sub": "abc", "name": "楊", "nickname": "Kimi", "preferred_username": "kimiyang"}"""
        )

        assertEquals("楊", profile.displayName)
    }

    @Test
    fun `falls through to username when names are absent`() {
        val profile = makeProfile("""{"sub": "abc", "preferred_username": "kimiyang"}""")

        assertEquals("kimiyang", profile.displayName)
    }

    /** Worst case the UI still shows something rather than an empty label. */
    @Test
    fun `falls back to sub when nothing is populated`() {
        assertEquals("abc-123", makeProfile("""{"sub": "abc-123"}""").displayName)
    }
}

class ProfileSchoolTest {

    @Test
    fun `recognised school domains map to their abbreviation`() {
        val cases = mapOf(
            "kimi@u.nus.edu" to "NUS",
            "kimi@nus.edu.sg" to "NUS",
            "kimi@e.ntu.edu.sg" to "NTU",
            "kimi@ntu.edu.sg" to "NTU",
            "kimi@smu.edu.sg" to "SMU",
            "kimi@sutd.edu.sg" to "SUTD",
        )

        for ((email, expected) in cases) {
            assertEquals(email, expected, makeProfile("""{"sub": "abc", "email": "$email"}""").school)
        }
    }

    /**
     * The domain is lowercased before matching, so a capitalised address from
     * authentik still resolves.
     */
    @Test
    fun `matches regardless of case`() {
        val profile = makeProfile("""{"sub": "abc", "email": "KIMI@U.NUS.EDU"}""")

        assertEquals("NUS", profile.school)
    }

    /**
     * This is inference from an email domain, not an authoritative claim — an
     * unknown domain must produce null rather than a plausible guess.
     */
    @Test
    fun `does not guess unknown domains`() {
        for (email in listOf("kimi@gmail.com", "kimi@mit.edu", "kimi@stsa.tw")) {
            assertNull(email, makeProfile("""{"sub": "abc", "email": "$email"}""").school)
        }
    }

    @Test
    fun `returns null when there is no email at all`() {
        assertNull(makeProfile("""{"sub": "abc"}""").school)
    }

    /**
     * Matching is by suffix, so a domain that merely *ends* with a school's
     * domain is accepted. `bonus.edu.sg` is not a real registrar entry, and the
     * claim is UI-only, so this is recorded rather than treated as a defect — if
     * the match ever tightens to a dot boundary, this expectation flips. The
     * same case is pinned on iOS.
     */
    @Test
    fun `suffix matching accepts domains that merely end with a school domain`() {
        val profile = makeProfile("""{"sub": "abc", "email": "kimi@bonus.edu.sg"}""")

        assertEquals("NUS", profile.school)
    }
}

class ProfileOfficerTest {

    /**
     * Drives UI only — never a security boundary. The test pins the exact group
     * name, which is the part a rename would silently break.
     */
    @Test
    fun `officer group is matched exactly`() {
        val officer = makeProfile("""{"sub": "abc", "groups": ["STSA 幹部"]}""")
        val member = makeProfile("""{"sub": "abc", "groups": ["STSA 會員"]}""")

        assertTrue(officer.isOfficer)
        assertFalse(member.isOfficer)
    }
}
