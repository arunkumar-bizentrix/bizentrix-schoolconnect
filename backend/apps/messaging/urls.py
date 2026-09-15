from django.urls import path

from .views import ContactsView, ConversationDetailView, ConversationListView, MessageCreateView, UnreadCountView

urlpatterns = [
    path('messages/conversations/', ConversationListView.as_view(), name='conversations'),
    path('messages/conversations/<int:pk>/', ConversationDetailView.as_view(), name='conversation_detail'),
    path('messages/conversations/<int:pk>/messages/', MessageCreateView.as_view(), name='conversation_messages'),
    path('messages/contacts/', ContactsView.as_view(), name='message_contacts'),
    path('messages/unread-count/', UnreadCountView.as_view(), name='messages_unread_count'),
]
