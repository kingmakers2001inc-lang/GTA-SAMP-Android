package com.kingmakers.rp.launcher

/** Same rule as server/gamemodes/grand_rp.pwn: Firstname_Lastname, letters only, both capitalised. */
object RpName {
    private val pattern = Regex("^[A-Z][a-z]+_[A-Z][a-z]+$")

    fun isValid(name: String): Boolean = name.length in 5..24 && pattern.matches(name)
}
