from django.conf import settings
from django.db import models
from django.db.models import F, Q


class Conversation(models.Model):
    """
    A private thread between exactly two people of the school.

    The pair is stored in id order (user_low < user_high) so there is only
    ever one conversation between the same two people, whoever wrote first.
    """

    school = models.ForeignKey('schools.School', on_delete=models.CASCADE, related_name='conversations')
    user_low = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')
    user_high = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')
    created_at = models.DateTimeField(auto_now_add=True)
    last_message_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ['-last_message_at']
        constraints = [
            models.UniqueConstraint(fields=['user_low', 'user_high'], name='one_conversation_per_pair'),
            models.CheckConstraint(condition=Q(user_low__lt=F('user_high')), name='conversation_pair_in_id_order'),
        ]

    def participant_ids(self):
        return (self.user_low_id, self.user_high_id)

    def other_participant(self, user):
        return self.user_high if user.id == self.user_low_id else self.user_low

    def __str__(self):
        return f'Conversation {self.user_low_id} <-> {self.user_high_id}'


class Message(models.Model):
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name='messages')
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='messages_sent')
    body = models.TextField(max_length=2000)
    created_at = models.DateTimeField(auto_now_add=True)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['created_at', 'id']
        indexes = [
            models.Index(fields=['conversation', 'created_at']),
            models.Index(fields=['conversation', 'read_at']),
        ]

    def __str__(self):
        return f'Message {self.id} in {self.conversation_id}'
