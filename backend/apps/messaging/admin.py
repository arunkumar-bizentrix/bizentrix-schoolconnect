from django.contrib import admin

from .models import Conversation


@admin.register(Conversation)
class ConversationAdmin(admin.ModelAdmin):
    # Message bodies are private between the two people; the admin site shows
    # who talked, not what was said.
    list_display = ('id', 'user_low', 'user_high', 'last_message_at')
    raw_id_fields = ('user_low', 'user_high')
