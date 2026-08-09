package tw.stsa.memberapp

import android.app.Application
import tw.stsa.memberapp.app.AppContainer

class MemberApplication : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
