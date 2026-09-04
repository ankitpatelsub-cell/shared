package dev.termvault.app.navigation

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Mirrors iOS `AppNavigationStore`. */
class AppNavigationStore {
    private val _selectedTab = MutableStateFlow(RootTab.HOSTS)
    val selectedTab: StateFlow<RootTab> = _selectedTab.asStateFlow()

    private var previousTab: RootTab = RootTab.HOSTS

    fun navigate(to: RootTab) {
        if (to == _selectedTab.value) return
        previousTab = _selectedTab.value
        _selectedTab.value = to
    }

    fun goBack(fallback: RootTab = RootTab.HOSTS) {
        val destination = if (previousTab == RootTab.SESSIONS) fallback else previousTab
        previousTab = _selectedTab.value
        _selectedTab.value = destination
    }
}
